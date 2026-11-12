//! Parse justfile recipes into sections from '# TITLE ===' separator blocks.
use anyhow::Result;
use regex::Regex;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Recipe {
    pub name: String,
    /// Raw recipe name + param spec as written, e.g. `update *args`
    pub spec: String,
    pub doc: String,
    pub params: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct Section {
    pub title: String,
    pub recipes: Vec<Recipe>,
}

#[derive(Debug)]
pub struct Justfile {
    pub sections: Vec<Section>,
}

impl Justfile {
    pub fn all_recipes(&self) -> Vec<(usize, usize)> {
        let mut v = Vec::new();
        for (si, s) in self.sections.iter().enumerate() {
            for (ri, _r) in s.recipes.iter().enumerate() {
                v.push((si, ri));
            }
        }
        v
    }
}

pub fn parse(path: &Path) -> Result<Justfile> {
    let text = fs::read_to_string(path)?;
    let lines: Vec<&str> = text.lines().collect();

    // Detect header blocks: '# ===...' / '# TITLE' / '# ===...'
    let is_sep = |s: &str| -> bool {
        let t = s.trim();
        t.starts_with('#')
            && t.trim_start_matches('#')
                .trim()
                .chars()
                .all(|ch| ch == '=' || ch == ' ')
    };
    let mut header_title_at: Vec<(usize, String)> = Vec::new();
    let mut i = 0usize;
    while i + 2 < lines.len() {
        let (a, b, c) = (lines[i].trim(), lines[i + 1].trim(), lines[i + 2].trim());
        if is_sep(a) && is_sep(c) && b.starts_with("# ") {
            header_title_at.push((i, b.trim_start_matches('#').trim().to_string()));
            i += 3;
            continue;
        }
        i += 1;
    }

    let mut sections: Vec<Section> = Vec::new();
    let mut doc_buf: Vec<String> = Vec::new();
    let mut header_idx = 0usize;
    let recipe_re = Regex::new(r"^([a-zA-Z_][a-zA-Z0-9_-]*)((?:\s+[^:]*?)?)\s*:\s*$")?;

    for (ln, raw) in lines.iter().enumerate() {
        let line = raw.trim_end();
        let trimmed = line.trim();

        if header_idx < header_title_at.len() && header_title_at[header_idx].0 == ln {
            header_idx += 1;
            doc_buf.clear();
            sections.push(Section {
                title: header_title_at[header_idx - 1].1.clone(),
                recipes: Vec::new(),
            });
            continue;
        }

        // Separator lines (standalone) end doc context too
        if is_sep(trimmed) {
            doc_buf.clear();
            continue;
        }

        // Comment lines only matter as docs when at column 0
        if trimmed.starts_with('#') && !trimmed.starts_with("#!") {
            if line.starts_with('#') {
                doc_buf.push(trimmed.trim_start_matches('#').trim().to_string());
            } else {
                doc_buf.clear(); // indented comment = recipe body
            }
            continue;
        }

        // Recipe definitions only appear at column 0 (body lines are indented)
        if trimmed.is_empty() || line.starts_with(' ') || line.starts_with('\t') {
            if !trimmed.is_empty() {
                doc_buf.clear();
            }
            continue;
        }

        if let Some(cap) = recipe_re.captures(trimmed) {
            let name = cap[1].to_string();
            let params_spec = cap.get(2).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
            let doc = doc_buf.join("\n");
            doc_buf.clear();
            if name != "default" {
                let params = parse_params(&format!("{name} {params_spec}"));
                let r = Recipe {
                    name: name.clone(),
                    spec: format!("{name} {params_spec}").trim().to_string(),
                    doc,
                    params,
                };
                match sections.last_mut() {
                    Some(s) => s.recipes.push(r),
                    None => sections.push(Section {
                        title: "UNSORTED".to_string(),
                        recipes: vec![r],
                    }),
                }
            }
            continue;
        }

        doc_buf.clear();
    }

    sections.retain(|s| !s.recipes.is_empty());
    normalize_titles(&mut sections);
    Ok(Justfile { sections })
}

/// Collapse verbose backup banner titles into clean "BACKUPS — X" labels.
fn normalize_title(raw: &str) -> String {
    let upper = raw.to_uppercase();
    for (prefix, label) in [
        ("BACKUP NEXTCLOUD", "BACKUPS — NEXTCLOUD"),
        ("BACKUP ATHENA", "BACKUPS — ATHENA"),
        ("BACKUP IMMICH", "BACKUPS — IMMICH"),
        ("BACKUP HONCHO", "BACKUPS — HONCHO"),
    ] {
        if upper.starts_with(prefix) {
            return label.to_string();
        }
    }
    raw.to_string()
}

fn normalize_titles(sections: &mut [Section]) {
    for s in sections.iter_mut() {
        s.title = normalize_title(&s.title);
    }
}

/// Extract parameter names from a recipe spec, ignoring quoted default values.
fn parse_params(spec: &str) -> Vec<String> {
    // Remove quoted strings (defaults may contain spaces)
    let mut cleaned = String::new();
    let mut in_q = false;
    for ch in spec.chars() {
        if ch == '"' {
            in_q = !in_q;
            continue;
        }
        if !in_q {
            cleaned.push(ch);
        }
    }
    let mut out = Vec::new();
    for tok in cleaned.split_whitespace().skip(1) {
        let t = tok.trim_start_matches(['*', '+']).split('=').next().unwrap_or("").to_string();
        if !t.is_empty() {
            out.push(t);
        }
    }
    out
}

pub fn print_tree(jf: &Justfile) {
    for s in &jf.sections {
        println!("SECTION: {}", s.title);
        for r in &s.recipes {
            let params = if r.params.is_empty() {
                String::new()
            } else {
                format!("  [params: {}]", r.params.join(", "))
            };
            let first_doc = r.doc.lines().next().unwrap_or("");
            println!("  - {}{}  # {}", r.name, params, first_doc);
        }
    }
}
