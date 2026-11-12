//! Event loop: raw-mode terminal, SIGWINCH resize, key handling, PTY run pump.

use crate::app::{App, Mode};
use crate::runner::{self, PtyRun};
use crossterm::event::{self, Event, KeyCode, KeyModifiers};
use std::path::Path;
use std::time::Duration;

struct Active {
    run: PtyRun,
}

#[derive(PartialEq)]
enum Handle {
    Continue,
    Exit,
}

pub fn run_app(app: &mut App, cwd: &Path) -> anyhow::Result<()> {
    let mut term = crate::term::init()?;
    let res = event_loop(app, cwd, &mut term);
    crate::term::restore(&mut term)?;
    res
}

fn event_loop(
    app: &mut App,
    cwd: &Path,
    term: &mut crate::term::TuiTerminal,
) -> anyhow::Result<()> {
    let mut active: Option<Active> = None;
    let mut buf = vec![0u8; 8192];

    loop {
        if app.mode == Mode::Running {
            if let Some(a) = active.as_mut() {
                match runner::read_chunk(&mut a.run.reader, &mut buf) {
                    Ok(0) => {}
                    Ok(n) => {
                        let s = String::from_utf8_lossy(&buf[..n]).into_owned();
                        app.push_output(&s);
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                    Err(_) => {}
                }
                match a.run.child.try_wait() {
                    Ok(Some(status)) => {
                        let code = status.exit_code();
                        let msg = if code == 0 {
                            String::new()
                        } else {
                            format!("(exit {})", code)
                        };
                        app.finish_run(code == 0, msg);
                    }
                    Ok(None) => {}
                    Err(e) => app.finish_run(false, format!("wait error: {}", e)),
                }
            }
        }

        term.view().draw(|f| crate::ui::draw(f, app))?;
        term.flush()?;

        if term.take_winch() {
            if let Some(a) = active.as_ref() {
                let (rows, cols) = term.size();
                runner::resize(&*a.run.master, rows, cols);
            }
        }

        if event::poll(Duration::from_millis(30))? {
            match event::read()? {
                Event::Key(key) => {
                    if handle_key(app, cwd, key, &mut active) == Handle::Exit
                        && app.mode != Mode::Running
                    {
                        return Ok(());
                    }
                }
                Event::Resize(_, _) => {
                    term.on_resize();
                    if let Some(a) = active.as_ref() {
                        let (rows, cols) = term.size();
                        runner::resize(&*a.run.master, rows, cols);
                    }
                }
                _ => {}
            }
        }
    }
}

fn handle_key(
    app: &mut App,
    cwd: &Path,
    key: crossterm::event::KeyEvent,
    active: &mut Option<Active>,
) -> Handle {
    match app.mode {
        Mode::Menu => menu_key(app, key),
        Mode::Search => search_key(app, key),
        Mode::Args => args_key(app, key),
        Mode::Confirm => confirm_key(app, cwd, key, active),
        Mode::Running => running_key(app, key, active),
        Mode::Finished => {
            if key.code == KeyCode::Enter {
                app.mode = Mode::Menu;
                app.pending_recipe = None;
                app.args_buf.clear();
                *active = None;
            }
            Handle::Continue
        }
    }
}

fn menu_key(app: &mut App, key: crossterm::event::KeyEvent) -> Handle {
    match key.code {
        KeyCode::Char('q') | KeyCode::Esc => return Handle::Exit,
        KeyCode::Char('j') | KeyCode::Down => app.move_down(),
        KeyCode::Char('k') | KeyCode::Up => app.move_up(),
        KeyCode::Tab => app.cycle_section(1),
        KeyCode::BackTab => app.cycle_section(-1),
        KeyCode::Char('/') => {
            app.mode = Mode::Search;
            app.query.clear();
            app.filtered = app.run_query();
            app.filtered_idx = 0;
        }
        KeyCode::Enter => {
            if let Some((_, r)) = app.highlighted() {
                let (name, params) = (r.name.clone(), r.params.clone());
                let has_params = !r.params.is_empty();
                app.pending_recipe = Some((name, params));
                app.args_buf.clear();
                app.mode = if has_params { Mode::Args } else { Mode::Confirm };
            }
        }
        _ => {}
    }
    Handle::Continue
}

fn search_key(app: &mut App, key: crossterm::event::KeyEvent) -> Handle {
    match key.code {
        KeyCode::Esc => {
            app.mode = Mode::Menu;
            app.query.clear();
        }
        KeyCode::Enter => {
            if let Some((si, ri)) = app.filtered.get(app.filtered_idx).copied() {
                let r = app.sections[si].recipes[ri].clone();
                app.section_idx = si;
                app.recipe_idx = ri;
                let has_params = !r.params.is_empty();
                app.pending_recipe = Some((r.name.clone(), r.params.clone()));
                app.args_buf.clear();
                app.mode = if has_params { Mode::Args } else { Mode::Confirm };
            }
        }
        KeyCode::Backspace => {
            app.query.pop();
            app.filtered = app.run_query();
            app.filtered_idx = 0;
        }
        KeyCode::Up | KeyCode::Char('k') => app.move_up(),
        KeyCode::Down | KeyCode::Char('j') => app.move_down(),
        KeyCode::Char(c) => {
            app.query.push(c);
            app.filtered = app.run_query();
            app.filtered_idx = 0;
        }
        _ => {}
    }
    Handle::Continue
}

fn args_key(app: &mut App, key: crossterm::event::KeyEvent) -> Handle {
    match key.code {
        KeyCode::Esc => {
            app.mode = Mode::Menu;
            app.args_buf.clear();
            app.pending_recipe = None;
        }
        KeyCode::Enter => app.mode = Mode::Confirm,
        KeyCode::Backspace => {
            app.args_buf.pop();
        }
        KeyCode::Char(c) => app.args_buf.push(c),
        _ => {}
    }
    Handle::Continue
}

fn confirm_key(
    app: &mut App,
    cwd: &Path,
    key: crossterm::event::KeyEvent,
    active: &mut Option<Active>,
) -> Handle {
    match key.code {
        KeyCode::Char('y') | KeyCode::Char('Y') => {
            let Some((name, params)) = app.pending_recipe.clone() else {
                app.mode = Mode::Menu;
                return Handle::Continue;
            };
            let args = split_args(&app.args_buf);
            let (rows, cols) = crossterm::terminal::size().unwrap_or((24, 80));
            match runner::spawn_pty(&name, &args, cwd, rows, cols) {
                Ok(run) => {
                    app.args_buf.clear();
                    app.begin_run(&name, &params);
                    *active = Some(Active { run });
                }
                Err(e) => {
                    app.run_recipe = name;
                    app.run_lines.clear();
                    app.finish_run(false, format!("spawn failed: {}", e));
                }
            }
        }
        KeyCode::Char('n') | KeyCode::Char('N') | KeyCode::Esc => {
            app.mode = Mode::Menu;
            app.args_buf.clear();
            app.pending_recipe = None;
        }
        _ => {}
    }
    Handle::Continue
}

fn running_key(
    app: &mut App,
    key: crossterm::event::KeyEvent,
    active: &mut Option<Active>,
) -> Handle {
    match key.code {
        KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
            if let Some(a) = active.as_mut() {
                let _ = a.run.child.kill();
            }
            app.finish_run(false, "(killed by Ctrl-C)".into());
        }
        KeyCode::Up => app.run_scroll = app.run_scroll.saturating_sub(1),
        KeyCode::Down => {
            let max = app.run_lines.len().saturating_sub(1) as u16;
            app.run_scroll = (app.run_scroll + 1).min(max);
        }
        _ => {}
    }
    Handle::Continue
}

fn split_args(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut quote: Option<char> = None;
    for ch in s.chars() {
        match quote {
            Some(q) if ch == q => quote = None,
            Some(_) => cur.push(ch),
            None => match ch {
                '\'' | '"' => quote = Some(ch),
                c if c.is_whitespace() => {
                    if !cur.is_empty() {
                        out.push(std::mem::take(&mut cur));
                    }
                }
                c => cur.push(c),
            },
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}
