//! Application state: mode machine, selection, search filter, run view buffer.

use crate::parser::Section;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Menu,    // browsing sections/recipes
    Search,  // typing a filter
    Args,    // typing args for a parameterised recipe
    Confirm, // y/n confirmation
    Running, // child process running (PTY)
    Finished, // run view with SUCCESS/FAILED banner, ENTER closes
}

pub struct App {
    pub sections: Vec<Section>,
    pub section_idx: usize,
    pub recipe_idx: usize,
    pub mode: Mode,

    pub query: String,
    pub filtered: Vec<(usize, usize)>,
    pub filtered_idx: usize,

    pub args_buf: String,

    pub run_lines: Vec<String>,
    pub run_scroll: u16,
    pub run_recipe: String,
    pub run_success: Option<bool>,
    pub run_exit_msg: String,

    pub pending_recipe: Option<(String, Vec<String>)>,
}

impl App {
    pub fn new(sections: Vec<Section>) -> Self {
        Self {
            sections,
            section_idx: 0,
            recipe_idx: 0,
            mode: Mode::Menu,
            query: String::new(),
            filtered: Vec::new(),
            filtered_idx: 0,
            args_buf: String::new(),
            run_lines: Vec::new(),
            run_scroll: 0,
            run_recipe: String::new(),
            run_success: None,
            run_exit_msg: String::new(),
            pending_recipe: None,
        }
    }

    pub fn current_section(&self) -> Option<&Section> {
        self.sections.get(self.section_idx)
    }

    pub fn highlighted(&self) -> Option<(usize, &crate::parser::Recipe)> {
        if self.mode == Mode::Search {
            let (si, ri) = *self.filtered.get(self.filtered_idx)?;
            Some((si, self.sections.get(si)?.recipes.get(ri)?))
        } else {
            let s = self.current_section()?;
            let r = s.recipes.get(self.recipe_idx)?;
            Some((self.section_idx, r))
        }
    }

    pub fn run_query(&self) -> Vec<(usize, usize)> {
        let q = self.query.to_lowercase();
        let mut out = Vec::new();
        for (si, s) in self.sections.iter().enumerate() {
            for (ri, r) in s.recipes.iter().enumerate() {
                if q.is_empty()
                    || r.name.to_lowercase().contains(&q)
                    || r.doc.to_lowercase().contains(&q)
                    || s.title.to_lowercase().contains(&q)
                {
                    out.push((si, ri));
                }
            }
        }
        out
    }

    pub fn move_up(&mut self) {
        match self.mode {
            Mode::Search => {
                self.filtered_idx = self.filtered_idx.saturating_sub(1);
            }
            _ => {
                self.recipe_idx = self.recipe_idx.saturating_sub(1);
            }
        }
    }

    pub fn move_down(&mut self) {
        match self.mode {
            Mode::Search => {
                if self.filtered_idx + 1 < self.filtered.len() {
                    self.filtered_idx += 1;
                }
            }
            _ => {
                let len = self.current_section().map(|s| s.recipes.len()).unwrap_or(0);
                if self.recipe_idx + 1 < len {
                    self.recipe_idx += 1;
                }
            }
        }
    }

    pub fn cycle_section(&mut self, dir: i32) {
        if self.sections.is_empty() {
            return;
        }
        let n = self.sections.len() as i32;
        self.section_idx = ((self.section_idx as i32 + dir).rem_euclid(n)) as usize;
        self.recipe_idx = 0;
    }

    pub fn begin_run(&mut self, name: &str, raw_params: &[String]) {
        self.run_recipe = name.to_string();
        self.run_lines.clear();
        self.run_scroll = 0;
        self.run_success = None;
        self.run_exit_msg.clear();
        self.pending_recipe = Some((name.to_string(), raw_params.to_vec()));
        self.mode = Mode::Running;
    }

    pub fn push_output(&mut self, chunk: &str) {
        let mut carry = String::new();
        for ch in chunk.chars() {
            if ch == '\n' {
                self.run_lines.push(std::mem::take(&mut carry));
            } else if ch != '\r' {
                carry.push(ch);
            }
        }
        if !carry.is_empty() {
            self.run_lines.push(carry);
        }
        let max = self.run_lines.len().saturating_sub(1) as u16;
        self.run_scroll = self.run_scroll.min(max);
    }

    pub fn finish_run(&mut self, success: bool, msg: String) {
        self.run_success = Some(success);
        self.run_exit_msg = msg;
        self.mode = Mode::Finished;
        let max = self.run_lines.len().saturating_sub(1) as u16;
        self.run_scroll = max;
    }

    pub fn run_params_spec(&self) -> Vec<String> {
        self.pending_recipe
            .as_ref()
            .map(|(_, p)| p.clone())
            .unwrap_or_default()
    }
}
