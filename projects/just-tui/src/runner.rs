//! PTY-based recipe execution with streaming output capture.
use anyhow::{anyhow, Result};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::io::Read;
use std::sync::mpsc::{channel, Receiver, TryRecvError};
use std::thread;

pub struct RunHandle {
    pub rx: Receiver<Event>,
    pub child: Box<dyn portable_pty::Child + Send + Sync>,
    pub writer: Box<dyn std::io::Write + Send>,
}

pub enum Event {
    Output(Vec<u8>),
    Exited(Option<u32>),
}

pub fn spawn(justfile: &std::path::Path, recipe: &str, args: &[String]) -> Result<RunHandle> {
    let pty_system = native_pty_system();
    let pair = pty_system.openpty(PtySize {
        rows: 40,
        cols: 120,
        pixel_width: 0,
        pixel_height: 0,
    })?;

    let mut cmd = CommandBuilder::new("just");
    cmd.arg("--justfile");
    cmd.arg(justfile);
    cmd.arg(recipe);
    for a in args {
        cmd.arg(a);
    }
    cmd.cwd(justfile.parent().unwrap_or(&std::path::PathBuf::from(".")));
    cmd.env("TERM", "xterm-256color");

    let child = pair.slave.spawn_command(cmd)?;
    drop(pair.slave);

    let mut reader = pair.master.try_clone_reader()?;
    let writer = pair.master.take_writer()?;
    let (tx, rx) = channel::<Event>();

    // Reader thread: stream combined stdout+stderr (PTY merges them).
    thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if tx.send(Event::Output(buf[..n].to_vec())).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });

    // Exit watcher thread.
    let mut child2_handle: Option<Box<dyn portable_pty::Child + Send + Sync>> = None;
    // We cannot easily clone child; instead poll wait in the main loop below.
    let _ = child2_handle.take();

    Ok(RunHandle { rx, child, writer })
}

impl RunHandle {
    /// Poll output; returns events accumulated. Checks child exit status.
    pub fn poll(&mut self, sink: &mut Vec<u8>) -> Result<Option<u32>> {
        loop {
            match self.rx.try_recv() {
                Ok(Event::Output(data)) => sink.extend_from_slice(&data),
                Ok(Event::Exited(code)) => return Ok(code),
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => break,
            }
        }
        // Check if child exited (non-blocking via try_wait)
        match self.child.try_wait()? {
            Some(status) => Ok(Some(status.exit_code())),
            None => Ok(None),
        }
    }

    /// Kill the child process group (Ctrl-C handler path).
    pub fn kill(&mut self) {
        let _ = self.child.kill();
    }
}

pub fn show_recipe(justfile: &std::path::Path, recipe: &str) -> Result<String> {
    let out = std::process::Command::new("just")
        .arg("--justfile")
        .arg(justfile)
        .arg("--show")
        .arg(recipe)
        .output()?;
    if !out.status.success() {
        return Err(anyhow!("just --show {} failed: {}", recipe, String::from_utf8_lossy(&out.stderr)));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

pub fn list_recipes(justfile: &std::path::Path) -> Result<String> {
    let out = std::process::Command::new("just")
        .arg("--justfile")
        .arg(justfile)
        .arg("--list")
        .arg("--list-heading")
        .arg("")
        .output()?;
    if !out.status.success() {
        return Err(anyhow!("just --list failed: {}", String::from_utf8_lossy(&out.stderr)));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}
