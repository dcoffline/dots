//! ratatui UI: two-pane linutil layout + preview + run view.
use crate::parser::{Justfile, Recipe};
use crate::runner::{self, RunHandle};
use anyhow::Result;
use crossterm::event::{self, Event as CEvent, KeyCode, KeyEvent, KeyModifiers};
use crossterm::terminal::{enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::prelude::*;
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap};
use std::path::PathBuf;
use std::time::{Duration, Instant};

#[derive(PartialEq)]
enum Mode {
    Menu,
    ArgInput,
    Confirm,
    Running,
    Done,
}

struct App {
    jf: Justfile,
    justfile: PathBuf,
    section: ListState,
    recipe: ListState,
    mode: Mode,
    search: Option<String>,
    preview: String,
    run_output: Vec<u8>,
    run_handle: Option<RunHandle>,
    run_recipe: String,
    run_success: Option<bool>,
    arg_buf: String,
    current_params: Vec<String>,
    arg_idx: usize,
    collected_args: Vec<String>,
    should_quit: bool,
    filter: Option<String>,
}

impl App {
    fn filtered(&self) -> Vec<(usize, usize)> {
        match &self.filter {
            None => self.jf.all_recipes(),
            Some(f) => {
                let fl = f.to_lowercase();
                self.jf
                    .all_recipes()
                    .into_iter()
                    .filter(|(si, ri)| {
                        let r = &self.jf.sections[*si].recipes[*ri];
                        r.name.to_lowercase().contains(&fl)
                            || r.doc.to_lowercase().contains(&fl)
                    })
                    .collect()
            }
        }
    }

    fn selected(&self) -> Option<(usize, usize)> {
        let list = self.filtered();
        let idx = self.recipe_state().selected().unwrap_or(0);
        list.get(idx.min(list.len().saturating_sub(1))).copied()
    }

    fn recipe_state(&self) -> &ListState {
        &self.recipe
    }

    fn refresh_preview(&mut self) {
        if let Some((si, ri)) = self.selected() {
            let r = &self.jf.sections[si].recipes[ri];
            self.preview = runner::show_recipe(&self.justfile, &r.name).unwrap_or_default();
        }
    }

    fn move_selection(&mut self, delta: isize) {
        let len = self.filtered().len();
        if len == 0 {
            return;
        }
        let cur = self.recipe_state().selected().unwrap_or(0) as isize;
        let next = (cur + delta).clamp(0, len as isize - 1) as usize;
        self.recipe.select(Some(next));
        self.refresh_preview();
    }
}

pub fn run(justfile: PathBuf, jf: Justfile) -> Result<()> {
    enable_raw_mode()?;
    let mut stdout = std::io::stdout();
    crossterm::execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut term = Terminal::new(backend)?;

    let mut app = App {
        jf,
        justfile,
        section: ListState::default(),
        recipe: ListState::default(),
        mode: Mode::Menu,
        search: None,
        preview: String::new(),
        run_output: Vec::new(),
        run_handle: None,
        run_recipe: String::new(),
        run_success: None,
        arg_buf: String::new(),
        current_params: Vec::new(),
        arg_idx: 0,
        collected_args: Vec::new(),
        should_quit: false,
        filter: None,
    };
    app.recipe.select(Some(0));
    app.refresh_preview();

    let res = event_loop(&mut term, &mut app);

    crossterm::execute!(std::io::stdout(), LeaveAlternateScreen)?;
    crossterm::terminal::disable_raw_mode()?;
    res
}

fn event_loop(term: &mut Terminal<CrosstermBackend<std::io::Stdout>>, app: &mut App) -> Result<()> {
    let tick = Duration::from_millis(50);
    let mut last_tick = Instant::now();

    while !app.should_quit {
        term.draw(|f| draw(f, app))?;

        let timeout = tick.saturating_sub(last_tick.elapsed());
        if event::poll(timeout)? {
            if let CEvent::Key(key) = event::read()? {
                handle_key(app, key);
            }
            // Handle resize
            if let CEvent::Resize(_, _) = event::read().ok().unwrap_or(CEvent::Resize(0, 0)) {
                // ratatui auto-resizes on next draw
            }
        }
        // Poll running child
        if app.mode == Mode::Running {
            if let Some(h) = app.run_handle.as_mut() {
                if let Some(code) = h.poll(&mut app.run_output)? {
                    app.run_success = Some(code == 0);
                    app.mode = Mode::Done;
                }
            }
        }
        last_tick = Instant::now();
    }

    // Cleanup: kill any still-running child on quit
    if let Some(h) = app.run_handle.as_mut() {
        h.kill();
    }
    Ok(())
}

fn handle_key(app: &mut App, key: KeyEvent) {
    match app.mode {
        Mode::Menu => handle_menu_key(app, key),
        Mode::ArgInput => handle_arg_input(app, key),
        Mode::Confirm => handle_confirm(app, key),
        Mode::Running => handle_running(app, key),
        Mode::Done => handle_done(app, key),
    }
}

fn handle_menu_key(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Char('q') => app.should_quit = true,
        KeyCode::Esc => {
            if app.filter.is_some() {
                app.filter = None;
                app.recipe.select(Some(0));
            } else {
                app.should_quit = true;
            }
        }
        KeyCode::Char('/') => {
            app.filter = Some(String::new());
        }
        KeyCode::Down | KeyCode::Char('j') => app.move_selection(1),
        KeyCode::Up | KeyCode::Char('k') => app.move_selection(-1),
        KeyCode::Tab => next_section(app, 1),
        KeyCode::BackTab => next_section(app, -1),
        KeyCode::Enter => start_run_flow(app),
        _ => {
            if let Some(f) = app.filter.as_mut() {
                match key.code {
                    KeyCode::Char(c) => {
                        f.push(c);
                        app.recipe.select(Some(0));
                    }
                    KeyCode::Backspace => {
                        f.pop();
                        app.recipe.select(Some(0));
                    }
                    _ => {}
                }
            }
        }
    }
}

fn next_section(app: &mut App, dir: isize) {
    let n = app.jf.sections.len();
    if n == 0 {
        return;
    }
    let cur = app.section.selected().unwrap_or(0) as isize;
    let next = ((cur + dir) + n as isize) % n as isize;
    app.section.select(Some(next as usize));
    // Move selection to first recipe of that section
    if let Some(first) = app.filtered().iter().find(|(si, _)| *si == next as usize) {
        let list = app.filtered();
        if let Some(pos) = list.iter().position(|x| x == first) {
            app.recipe.select(Some(pos));
            app.refresh_preview();
        }
    }
}

fn start_run_flow(app: &mut App) {
    if let Some((si, ri)) = app.selected() {
        let r = app.jf.sections[si].recipes[ri].clone();
        if r.params.is_empty() {
            app.run_recipe = r.name.clone();
            app.mode = Mode::Confirm;
        } else {
            app.current_params = r.params.clone();
            app.collected_args = Vec::new();
            app.arg_idx = 0;
            app.arg_buf = String::new();
            app.mode = Mode::ArgInput;
        }
    }
}

fn handle_arg_input(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc => app.mode = Mode::Menu,
        KeyCode::Enter => {
            app.collected_args.push(app.arg_buf.clone());
            app.arg_buf.clear();
            app.arg_idx += 1;
            if app.arg_idx >= app.current_params.len() {
                app.mode = Mode::Confirm;
            }
        }
        KeyCode::Backspace => {
            app.arg_buf.pop();
        }
        KeyCode::Char(c) => app.arg_buf.push(c),
        _ => {}
    }
}

fn handle_confirm(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc => {
            app.mode = Mode::Menu;
        }
        KeyCode::Char('y') | KeyCode::Char('Y') => {
            // Launch in PTY
            let args: Vec<String> = app.collected_args.iter().filter(|s| !s.is_empty()).cloned().collect();
            app.run_output.clear();
            app.run_success = None;
            match runner::spawn(&app.justfile, &app.run_recipe, &args) {
                Ok(h) => {
                    app.run_handle = Some(h);
                    app.mode = Mode::Running;
                }
                Err(e) => {
                    app.run_output
                        .extend_from_slice(format!("Failed to spawn: {e}\n").as_bytes());
                    app.run_success = Some(false);
                    app.mode = Mode::Done;
                }
            }
        }
        KeyCode::Char('n') | KeyCode::Char('N') => {
            app.mode = Mode::Menu;
        }
        _ => {}
    }
}

fn handle_running(app: &mut App, key: KeyEvent) {
    if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
        if let Some(h) = app.run_handle.as_mut() {
            h.kill();
        }
    }
}

fn handle_done(app: &mut App, key: KeyEvent) {
    if key.code == KeyCode::Enter {
        app.run_handle = None;
        app.mode = Mode::Menu;
        app.run_output.clear();
    } else if key.code == KeyCode::Char('q') {
        app.should_quit = true;
    }
}

fn draw(f: &mut Frame, app: &mut App) {
    match app.mode {
        Mode::Running | Mode::Done => draw_run_view(f, app),
        _ => draw_menu(f, app),
    }
}

fn draw_menu(f: &mut Frame, app: &mut App) {
    let area = f.area();
    // Left tabs (narrow) | right recipe list; bottom preview pane.
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Length(26), Constraint::Min(20)])
        .split(area);
    let right = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(6), Constraint::Length(18)])
        .split(chunks[1]);

    // Left: sections
    let section_items: Vec<ListItem> = app
        .jf
        .sections
        .iter()
        .map(|s| ListItem::new(s.title.clone()).style(Style::default().fg(Color::Cyan)))
        .collect();
    let sec_list = List::new(section_items)
        .block(Block::default().borders(Borders::ALL).title(" Sections "))
        .highlight_style(Style::default().bg(Color::DarkGray).fg(Color::White));
    f.render_stateful_widget(sec_list, chunks[0], &mut app.section);

    // Right top: recipes of selected section (filtered)
    let list = app.filtered();
    let items: Vec<ListItem> = list
        .iter()
        .map(|(si, ri)| {
            let r = &app.jf.sections[*si].recipes[*ri];
            let mut name = r.name.clone();
            if !r.params.is_empty() {
                name.push_str(&format!(" [{}]", r.params.join(", ")));
            }
            let doc = r.doc.lines().next().unwrap_or("");
            ListItem::new(Line::from(vec![
                Span::styled(name, Style::default().fg(Color::Yellow)),
                Span::styled(format!("  {}", doc), Style::default().fg(Color::DarkGray)),
            ]))
        })
        .collect();
    let title = match &app.filter {
        Some(fstr) => format!(" Recipes (filter: /{}) ", fstr),
        None => " Recipes ".to_string(),
    };
    let rec_list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(title))
        .highlight_style(Style::default().bg(Color::DarkGray).fg(Color::White));
    f.render_stateful_widget(rec_list, right[0], &mut app.recipe);

    // Right bottom: preview from `just --show`
    let preview_text = if app.preview.is_empty() {
        "(no preview)".to_string()
    } else {
        app.preview.clone()
    };
    let preview = Paragraph::new(preview_text)
        .block(Block::default().borders(Borders::ALL).title(" Preview (just --show) "))
        .wrap(Wrap { trim: false });
    f.render_widget(preview, right[1]);

    // Overlays: arg input / confirm / search
    match app.mode {
        Mode::ArgInput => {
            let param = app.current_params.get(app.arg_idx).cloned().unwrap_or_default();
            let msg = format!("Argument for {{}}{}: {}", param, app.arg_buf);
            draw_centered_popup(f, area, " Recipe Argument ", &msg);
        }
        Mode::Confirm => {
            let msg = format!("Run `just {}`? (y/n)", app.run_recipe);
            draw_centered_popup(f, area, " Confirm ", &msg);
        }
        _ => {}
    }
}

fn draw_run_view(f: &mut Frame, app: &mut App) {
    let area = f.area();
    let text = String::from_utf8_lossy(&app.run_output);
    let status = match app.run_success {
        None => "RUNNING (Ctrl-C to kill)".to_string(),
        Some(true) => "SUCCESS — press ENTER to return".to_string(),
        Some(false) => "FAILED — press ENTER to return".to_string(),
    };
    let para = Paragraph::new(text.to_string())
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!(" just {} | {} ", app.run_recipe, status)),
        )
        .wrap(Wrap { trim: false })
        .scroll((scroll_for_len(text.len(), area.height), 0));
    f.render_widget(para, area);
}

fn scroll_for_len(len: usize, height: u16) -> u16 {
    let lines = len / 100; // approximate: count of lines-ish
    let h = height.saturating_sub(2) as usize;
    if lines > h {
        (lines - h).min(u16::MAX as usize) as u16
    } else {
        0
    }
}

fn draw_centered_popup(f: &mut Frame, area: Rect, title: &str, msg: &str) {
    let popup = centered_rect(60, 8, area);
    f.render_widget(clear::Clear, popup);
    let block = Block::default().borders(Borders::ALL).title(title).style(Style::default().bg(Color::Black));
    let para = Paragraph::new(msg).block(block).wrap(Wrap { trim: false });
    f.render_widget(para, popup);
}

mod clear {
    use ratatui::{buffer::Buffer, layout::Rect, widgets::Widget};
    pub struct Clear;
    impl Widget for Clear {
        fn render(self, area: Rect, buf: &mut Buffer) {
            for x in area.left()..area.right() {
                for y in area.top()..area.bottom() {
                    buf[(x, y)].set_char(' ');
                    buf[(x, y)].set_style(ratatui::style::Style::default());
                }
            }
        }
    }
}

fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);
    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}
