use std::collections::{BTreeSet, HashSet};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::localization::tr;
use crate::models::{Harness, Timestamp};
use crate::paths::Paths;
use crate::util::{last_path_component, modified, single_line, truncated};

pub const GLOBAL_SCOPE: &str = "Global";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RuleKind {
    Instructions,
    Skill,
    Hook,
    Agent,
    Command,
    Settings,
}

impl RuleKind {
    pub const ALL: [RuleKind; 6] =
        [RuleKind::Instructions, RuleKind::Skill, RuleKind::Hook, RuleKind::Agent, RuleKind::Command, RuleKind::Settings];

    pub fn label(self) -> String {
        match self {
            RuleKind::Instructions => tr("Rules"),
            RuleKind::Skill => tr("Skills"),
            RuleKind::Hook => tr("Hooks"),
            RuleKind::Agent => tr("Subagents"),
            RuleKind::Command => tr("Commands"),
            RuleKind::Settings => tr("Settings"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleItem {
    pub id: String,
    pub kind: RuleKind,
    pub harness: Harness,
    pub scope: String,
    pub name: String,
    pub path: String,
    pub summary: String,
    pub size: i64,
    pub modified_at: Option<Timestamp>,
}

impl RuleItem {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        kind: RuleKind,
        harness: Harness,
        scope: &str,
        name: &str,
        path: &str,
        summary: String,
        size: i64,
        modified_at: Option<Timestamp>,
    ) -> Self {
        RuleItem {
            id: Self::make_id(path, name),
            kind,
            harness,
            scope: scope.to_string(),
            name: name.to_string(),
            path: path.to_string(),
            summary,
            size,
            modified_at,
        }
    }

    pub fn make_id(path: &str, name: &str) -> String {
        format!("{path}#{name}")
    }

    fn with_path(mut self, path: &str) -> Self {
        self.path = path.to_string();
        self.id = Self::make_id(&self.path, &self.name);
        self
    }
}

const MARKDOWN_EXTENSIONS: &[&str] = &["md", "mdc"];
const TOML_EXTENSIONS: &[&str] = &["toml"];
const JSON_EXTENSIONS: &[&str] = &["json"];

pub fn scan(projects: &[String]) -> Vec<RuleItem> {
    let mut items = global_items();
    let roots: BTreeSet<String> = projects.iter().map(|project| project_root(project)).collect();
    for root in roots.iter().filter(|root| !root.is_empty()) {
        items.extend(project_items(root));
    }
    let mut seen = HashSet::new();
    items.retain(|item| seen.insert(item.id.clone()));
    items
}

pub fn project_root(cwd: &str) -> String {
    if cwd.is_empty() {
        return String::new();
    }
    for marker in ["/.claude/worktrees/", "\\.claude\\worktrees\\"] {
        if let Some(index) = cwd.find(marker) {
            return cwd[..index].to_string();
        }
    }
    let trimmed = cwd.trim_end_matches(['/', '\\']);
    let start = Path::new(if trimmed.is_empty() { cwd } else { trimmed });
    for directory in start.ancestors() {
        if directory.parent().is_none() || directory.as_os_str().is_empty() {
            break;
        }
        if directory.join(".git").exists() {
            return directory.to_string_lossy().into_owned();
        }
    }
    cwd.to_string()
}

pub fn global_items() -> Vec<RuleItem> {
    let scope = GLOBAL_SCOPE;
    let claude = Paths::claude();
    let codex = Paths::codex();
    let cursor = Paths::cursor();
    let gemini = Paths::gemini();
    let copilot = Paths::copilot();
    let mut items = Vec::new();
    items.extend(file(&claude.join("CLAUDE.md"), RuleKind::Instructions, Harness::Claude, scope, None));
    items.extend(file(&claude.join("settings.json"), RuleKind::Settings, Harness::Claude, scope, None));
    items.extend(hooks(&claude.join("settings.json"), Harness::Claude, scope));
    items.extend(skills(&claude.join("skills"), Harness::Claude, scope));
    items.extend(markdown_files(&claude.join("agents"), RuleKind::Agent, Harness::Claude, scope, MARKDOWN_EXTENSIONS));
    items.extend(markdown_files(&claude.join("commands"), RuleKind::Command, Harness::Claude, scope, MARKDOWN_EXTENSIONS));
    items.extend(markdown_files(&claude.join("rules"), RuleKind::Instructions, Harness::Claude, scope, MARKDOWN_EXTENSIONS));
    items.extend(file(&codex.join("AGENTS.md"), RuleKind::Instructions, Harness::Codex, scope, None));
    items.extend(file(&codex.join("config.toml"), RuleKind::Settings, Harness::Codex, scope, None));
    items.extend(codex_hooks(&codex.join("hooks.json"), scope));
    items.extend(skills(&codex.join("skills"), Harness::Codex, scope));
    items.extend(markdown_files(&cursor.join("rules"), RuleKind::Instructions, Harness::Cursor, scope, MARKDOWN_EXTENSIONS));
    items.extend(file(&Paths::pi().join("agent/AGENTS.md"), RuleKind::Instructions, Harness::Pi, scope, None));
    items.extend(file(&Paths::omp().join("agent/AGENTS.md"), RuleKind::Instructions, Harness::Omp, scope, None));
    items.extend(file(&gemini.join("GEMINI.md"), RuleKind::Instructions, Harness::Gemini, scope, None));
    items.extend(file(&gemini.join("settings.json"), RuleKind::Settings, Harness::Gemini, scope, None));
    items.extend(hooks(&gemini.join("settings.json"), Harness::Gemini, scope));
    items.extend(markdown_files(&gemini.join("commands"), RuleKind::Command, Harness::Gemini, scope, TOML_EXTENSIONS));
    items.extend(markdown_files(&gemini.join("agents"), RuleKind::Agent, Harness::Gemini, scope, MARKDOWN_EXTENSIONS));
    items.extend(skills(&gemini.join("skills"), Harness::Gemini, scope));
    items.extend(file(&copilot.join("copilot-instructions.md"), RuleKind::Instructions, Harness::Copilot, scope, None));
    items.extend(markdown_files(&copilot.join("instructions"), RuleKind::Instructions, Harness::Copilot, scope, MARKDOWN_EXTENSIONS));
    items.extend(file(&copilot.join("settings.json"), RuleKind::Settings, Harness::Copilot, scope, None));
    items.extend(hooks(&copilot.join("settings.json"), Harness::Copilot, scope));
    items.extend(file(&copilot.join("mcp-config.json"), RuleKind::Settings, Harness::Copilot, scope, None));
    items.extend(markdown_files(&copilot.join("agents"), RuleKind::Agent, Harness::Copilot, scope, MARKDOWN_EXTENSIONS));
    items.extend(markdown_files(&copilot.join("hooks"), RuleKind::Hook, Harness::Copilot, scope, JSON_EXTENSIONS));
    items.extend(skills(&copilot.join("skills"), Harness::Copilot, scope));
    items
}

pub fn project_items(root: &str) -> Vec<RuleItem> {
    let base = PathBuf::from(root);
    let scope_name = last_path_component(root);
    let scope = scope_name.as_str();
    let mut items = Vec::new();
    items.extend(file(&base.join("CLAUDE.md"), RuleKind::Instructions, Harness::Claude, scope, None));
    items.extend(file(&base.join("CLAUDE.local.md"), RuleKind::Instructions, Harness::Claude, scope, None));
    items.extend(file(&base.join(".claude/CLAUDE.md"), RuleKind::Instructions, Harness::Claude, scope, None));
    items.extend(file(&base.join("AGENTS.md"), RuleKind::Instructions, Harness::Codex, scope, None));
    items.extend(file(&base.join("GEMINI.md"), RuleKind::Instructions, Harness::Gemini, scope, None));
    items.extend(file(&base.join(".gemini/settings.json"), RuleKind::Settings, Harness::Gemini, scope, None));
    items.extend(hooks(&base.join(".gemini/settings.json"), Harness::Gemini, scope));
    items.extend(markdown_files(&base.join(".gemini/commands"), RuleKind::Command, Harness::Gemini, scope, TOML_EXTENSIONS));
    items.extend(markdown_files(&base.join(".github/instructions"), RuleKind::Instructions, Harness::Copilot, scope, MARKDOWN_EXTENSIONS));
    items.extend(markdown_files(&base.join(".github/agents"), RuleKind::Agent, Harness::Copilot, scope, MARKDOWN_EXTENSIONS));
    items.extend(markdown_files(&base.join(".github/hooks"), RuleKind::Hook, Harness::Copilot, scope, JSON_EXTENSIONS));
    items.extend(file(&base.join(".github/copilot/settings.json"), RuleKind::Settings, Harness::Copilot, scope, None));
    items.extend(file(&base.join(".cursorrules"), RuleKind::Instructions, Harness::Cursor, scope, None));
    items.extend(file(&base.join(".github/copilot-instructions.md"), RuleKind::Instructions, Harness::Copilot, scope, None));
    for name in ["settings.json", "settings.local.json"] {
        let path = base.join(".claude").join(name);
        items.extend(file(&path, RuleKind::Settings, Harness::Claude, scope, None));
        items.extend(hooks(&path, Harness::Claude, scope));
    }
    items.extend(skills(&base.join(".claude/skills"), Harness::Claude, scope));
    items.extend(skills(&base.join(".agents/skills"), Harness::Codex, scope));
    items.extend(markdown_files(&base.join(".claude/agents"), RuleKind::Agent, Harness::Claude, scope, MARKDOWN_EXTENSIONS));
    items.extend(markdown_files(&base.join(".claude/commands"), RuleKind::Command, Harness::Claude, scope, MARKDOWN_EXTENSIONS));
    items.extend(markdown_files(&base.join(".claude/rules"), RuleKind::Instructions, Harness::Claude, scope, MARKDOWN_EXTENSIONS));
    items.extend(markdown_files(&base.join(".cursor/rules"), RuleKind::Instructions, Harness::Cursor, scope, MARKDOWN_EXTENSIONS));
    items
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn file_name(path: &Path) -> String {
    path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default()
}

pub fn file(path: &Path, kind: RuleKind, harness: Harness, scope: &str, name: Option<&str>) -> Option<RuleItem> {
    let metadata = std::fs::metadata(path).ok()?;
    if metadata.is_dir() {
        return None;
    }
    let content = std::fs::read_to_string(path).unwrap_or_default();
    let fallback_name = file_name(path);
    Some(RuleItem::new(
        kind,
        harness,
        scope,
        name.unwrap_or(&fallback_name),
        &path_string(path),
        summary(&content),
        metadata.len() as i64,
        metadata.modified().ok().map(crate::util::system_time),
    ))
}

pub fn markdown_files(dir: &Path, kind: RuleKind, harness: Harness, scope: &str, extensions: &[&str]) -> Vec<RuleItem> {
    walkdir::WalkDir::new(dir)
        .min_depth(1)
        .sort_by_file_name()
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| {
            entry.path().extension().and_then(|ext| ext.to_str()).is_some_and(|ext| extensions.contains(&ext))
        })
        .filter_map(|entry| {
            let stem = entry.path().file_stem().map(|stem| stem.to_string_lossy().into_owned()).unwrap_or_default();
            file(entry.path(), kind, harness, scope, Some(&stem))
        })
        .collect()
}

pub fn sorted_entries(dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut paths: Vec<PathBuf> = entries.filter_map(Result::ok).map(|entry| entry.path()).collect();
    paths.sort();
    paths
}

pub fn resolving_symlinks(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

pub fn skills(dir: &Path, harness: Harness, scope: &str) -> Vec<RuleItem> {
    sorted_entries(dir)
        .into_iter()
        .filter_map(|entry| {
            let skill = entry.join("SKILL.md");
            let resolved = resolving_symlinks(&skill);
            file(&resolved, RuleKind::Skill, harness, scope, Some(&file_name(&entry)))
                .map(|item| item.with_path(&path_string(&skill)))
        })
        .collect()
}

pub fn hooks(settings: &Path, harness: Harness, scope: &str) -> Vec<RuleItem> {
    let Some(json) = std::fs::read(settings).ok().and_then(|data| serde_json::from_slice::<Value>(&data).ok()) else {
        return Vec::new();
    };
    let Some(hooks) = json.get("hooks").and_then(Value::as_object) else { return Vec::new() };
    let mut events: Vec<(&String, &Value)> = hooks.iter().collect();
    events.sort_by(|a, b| a.0.cmp(b.0));
    let modified_at = modified(settings);
    let path = path_string(settings);
    let mut items = Vec::new();
    for (event, value) in events {
        for group in value.as_array().into_iter().flatten().filter(|group| group.is_object()) {
            let matcher = group.get("matcher").and_then(Value::as_str);
            for hook in group.get("hooks").and_then(Value::as_array).into_iter().flatten().filter(|hook| hook.is_object()) {
                let command = hook
                    .get("command")
                    .and_then(Value::as_str)
                    .or_else(|| hook.get("type").and_then(Value::as_str))
                    .unwrap_or("?");
                let name = match matcher {
                    Some("") | None => event.clone(),
                    Some(matcher) => format!("{event} · {matcher}"),
                };
                items.push(RuleItem::new(
                    RuleKind::Hook,
                    harness,
                    scope,
                    &name,
                    &path,
                    truncated(&single_line(command), 160),
                    command.chars().count() as i64,
                    modified_at,
                ));
            }
        }
    }
    items
}

pub fn codex_hooks(path: &Path, scope: &str) -> Vec<RuleItem> {
    let Some(json) = std::fs::read(path).ok().and_then(|data| serde_json::from_slice::<Value>(&data).ok()) else {
        return Vec::new();
    };
    if json.as_object().is_some_and(|object| object.contains_key("hooks")) {
        return hooks(path, Harness::Codex, scope);
    }
    file(path, RuleKind::Hook, Harness::Codex, scope, None).into_iter().collect()
}

pub fn summary(content: &str) -> String {
    let mut body = content;
    if body.starts_with("---") {
        if let Some(offset) = body[3..].find("\n---") {
            let end = offset + 3;
            let front = &body[..end];
            if let Some(description) = front.split('\n').find(|line| line.starts_with("description:")) {
                let value = description["description:".len()..].trim_matches([' ', '"', '\'']);
                return truncated(value, 160);
            }
            body = &body[end + 4..];
        }
    }
    let line = body
        .split('\n')
        .map(str::trim)
        .find(|line| !line.is_empty() && !line.starts_with('{') && !line.starts_with('['))
        .unwrap_or("");
    truncated(line.trim_matches(['#', ' ']), 160)
}
