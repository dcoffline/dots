//! just-tui: linutil-style TUI for Eric's justfile.
mod parser;
mod runner;
mod ui;

use anyhow::{bail, Result};
use std::path::PathBuf;

fn main() -> Result<()> {
    let mut justfile_path: Option<PathBuf> = None;
    let mut print_parse = false;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--print-parse" => print_parse = true,
            "--justfile" => {
                justfile_path = args.next().map(PathBuf::from);
            }
            "--help" | "-h" => {
                println!("just-tui — linutil-style TUI for justfiles");
                println!("Usage: just-tui [--justfile PATH] [--print-parse]");
                println!("  --justfile PATH   justfile to use (default: ~/.justfile)");
                println!("  --print-parse     print parsed section->recipe tree and exit (headless test mode)");
                return Ok(());
            }
            other => bail!("unknown argument: {other} (try --help)"),
        }
    }

    let path = justfile_path.unwrap_or_else(|| {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
        PathBuf::from(home).join(".justfile")
    });

    let jf = parser::parse(&path)?;

    if print_parse {
        parser::print_tree(&jf);
        return Ok(());
    }

    ui::run(path, jf)
}
