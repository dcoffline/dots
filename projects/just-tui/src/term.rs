//! Terminal setup: raw mode, alternate screen, SIGWINCH flag, crossterm backend.

use anyhow::Result;
use crossterm::{
    event::EnableFocusChange,
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

pub struct TuiTerminal {
    term: Terminal<CrosstermBackend<std::io::Stdout>>,
    winch: Arc<AtomicBool>,
    handle: Option<std::thread::JoinHandle<()>>,
}

impl TuiTerminal {
    pub fn view(&mut self) -> &mut Terminal<CrosstermBackend<std::io::Stdout>> {
        &mut self.term
    }

    pub fn flush(&mut self) -> Result<()> {
        self.term.flush()?;
        Ok(())
    }

    pub fn take_winch(&mut self) -> bool {
        self.winch.swap(false, Ordering::Relaxed)
    }

    pub fn on_resize(&mut self) {
        let _ = self.term.autoresize();
    }

    pub fn size(&self) -> (u16, u16) {
        crossterm::terminal::size().unwrap_or((24, 80))
    }
}

pub fn init() -> Result<TuiTerminal> {
    enable_raw_mode()?;
    let mut stdout = std::io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableFocusChange)?;
    let backend = CrosstermBackend::new(stdout);
    let mut term = Terminal::new(backend)?;
    term.clear()?;

    let winch = Arc::new(AtomicBool::new(false));
    let flag = Arc::clone(&winch);
    let mut signals = signal_hook::iterator::Signals::new([signal_hook::consts::SIGWINCH])?;
    let handle = std::thread::spawn(move || {
        for _ in signals.forever() {
            flag.store(true, Ordering::Relaxed);
        }
    });

    Ok(TuiTerminal {
        term,
        winch,
        handle: Some(handle),
    })
}

pub fn restore(term: &mut TuiTerminal) -> Result<()> {
    if let Some(h) = term.handle.take() {
        let _ = h;
    }
    disable_raw_mode()?;
    execute!(std::io::stdout(), LeaveAlternateScreen)?;
    Ok(())
}
