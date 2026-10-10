use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::diff::{self, DiffLine};
use crate::localization::tr;
use crate::models::{AgentSession, Harness, Timestamp};
use crate::rules;
use crate::suggestions::{Suggestion, SuggestionEngine, SuggestionKind, SuggestionStatus};
use crate::trf;
use crate::util::{last_path_component, modified, trim_spaces};

pub const INSTRUCTION_FILES: [&str; 5] = ["CLAUDE.md", "AGENTS.md", "CLAUDE.local.md", ".cursorrules", "GEMINI.md"];
pub const EXPORT_LABEL: &str = ".boss/domain.md";

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DomainFact {
    pub text: String,
    pub source: String,
    pub date: Option<Timestamp>,
}

impl DomainFact {
    pub fn new(text: impl Into<String>, source: impl Into<String>, date: Option<Timestamp>) -> Self {
        DomainFact { text: text.into(), source: source.into(), date }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DomainModel {
    pub root: String,
    pub name: String,
    pub intent: String,
    pub conventions: Vec<DomainFact>,
    pub decisions: Vec<DomainFact>,
    pub activity: Vec<DomainFact>,
    pub agents: BTreeMap<Harness, i64>,
    pub conflicts: Vec<String>,
    pub export_path: String,
    pub markdown: String,
    pub export_diff: Vec<DiffLine>,
}

impl DomainModel {
    pub fn render_markdown(&self) -> String {
        let mut lines = vec![trf!("# %@ · domain model", &self.name), String::new()];
        let intent = if self.intent.is_empty() { tr("_To be written._") } else { self.intent.clone() };
        lines.extend([tr("## Intent"), String::new(), intent, String::new()]);
        if !self.conventions.is_empty() {
            lines.extend([tr("## Conventions"), String::new()]);
            lines.extend(self.conventions.iter().map(|fact| format!("- {}", fact.text)));
            lines.push(String::new());
        }
        if !self.decisions.is_empty() {
            lines.extend([tr("## Decisions"), String::new()]);
            lines.extend(self.decisions.iter().map(|fact| format!("- {} ({})", fact.text, fact.source)));
            lines.push(String::new());
        }
        if !self.activity.is_empty() {
            lines.extend([tr("## Recent work"), String::new()]);
            lines.extend(self.activity.iter().take(10).map(|fact| format!("- {} ({})", fact.text, fact.source)));
            lines.push(String::new());
        }
        lines.join("\n")
    }

    pub fn refresh_export(&mut self) {
        self.markdown = self.render_markdown();
        let current = std::fs::read_to_string(&self.export_path).unwrap_or_default();
        self.export_diff = diff::lines(&current, &self.markdown, EXPORT_LABEL, diff::DEFAULT_CONTEXT);
    }
}

pub fn export_path(root: &str) -> String {
    Path::new(root).join(EXPORT_LABEL).to_string_lossy().into_owned()
}

pub fn projects(sessions: &[AgentSession]) -> Vec<String> {
    let mut seen = HashSet::new();
    sessions
        .iter()
        .map(|session| rules::project_root(&session.cwd))
        .filter(|root| !root.is_empty())
        .filter(|root| seen.insert(root.clone()))
        .collect()
}

pub fn build(root: &str, intent: &str, sessions: &[AgentSession], suggestions: &[Suggestion]) -> DomainModel {
    let base = Path::new(root);
    let mut conventions = Vec::new();
    let mut decisions = Vec::new();
    let mut bullets_by_file: HashMap<&str, HashSet<String>> = HashMap::new();
    for file in INSTRUCTION_FILES {
        let path = base.join(file);
        let Ok(content) = std::fs::read_to_string(&path) else { continue };
        let mut in_learned = false;
        let mut in_code = false;
        for raw in content.split('\n') {
            let line = trim_spaces(raw);
            if line.starts_with("```") {
                in_code = !in_code;
                continue;
            }
            if in_code {
                continue;
            }
            if line.starts_with('#') {
                in_learned = SuggestionEngine::LEARNED_SECTIONS.contains(&line);
                continue;
            }
            if !line.starts_with("- ") && !line.starts_with("* ") {
                continue;
            }
            let text = trim_spaces(&line[2..]);
            if text.chars().count() < 6 {
                continue;
            }
            bullets_by_file.entry(file).or_default().insert(normalize(text));
            let fact = DomainFact::new(text, file, modified(&path));
            if in_learned {
                decisions.push(fact);
            } else {
                conventions.push(fact);
            }
        }
    }
    for file in rules::sorted_entries(&base.join(".cursor/rules")) {
        let file_name = last_path_component(&file.to_string_lossy());
        if !file_name.ends_with(".mdc") && !file_name.ends_with(".md") {
            continue;
        }
        let summary = rules::summary(&std::fs::read_to_string(&file).unwrap_or_default());
        if !summary.is_empty() {
            conventions.push(DomainFact::new(summary, format!(".cursor/rules/{file_name}"), None));
        }
    }
    let name = last_path_component(root);
    for suggestion in suggestions.iter().filter(|suggestion| {
        suggestion.kind == SuggestionKind::LearnedRule && suggestion.project == name && suggestion.status != SuggestionStatus::Dismissed
    }) {
        let status = if suggestion.status == SuggestionStatus::Applied { tr("applied") } else { tr("pending") };
        let title = normalize(&suggestion.title);
        if !decisions.iter().any(|fact: &DomainFact| normalize(&fact.text) == title) {
            decisions.push(DomainFact::new(suggestion.title.clone(), trf!("mail · %@", status), Some(suggestion.created_at)));
        }
    }
    let mut project_sessions: Vec<&AgentSession> =
        sessions.iter().filter(|session| rules::project_root(&session.cwd) == root).collect();
    project_sessions.sort_by_key(|session| std::cmp::Reverse(session.updated_at));
    let activity = project_sessions
        .iter()
        .map(|session| DomainFact::new(session.title.clone(), session.harness.display_name(), Some(session.updated_at)))
        .collect();
    let mut agents = BTreeMap::new();
    for session in &project_sessions {
        *agents.entry(session.harness).or_insert(0) += 1;
    }
    let mut model = DomainModel {
        root: root.to_string(),
        name,
        intent: intent.to_string(),
        conventions,
        decisions,
        activity,
        agents,
        conflicts: conflicts(&bullets_by_file),
        export_path: export_path(root),
        markdown: String::new(),
        export_diff: Vec::new(),
    };
    model.refresh_export();
    model
}

pub fn export(model: &DomainModel) -> std::io::Result<()> {
    let path = Path::new(&model.export_path);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let markdown = if model.markdown.is_empty() { model.render_markdown() } else { model.markdown.clone() };
    std::fs::write(path, markdown)
}

pub fn conflicts(bullets_by_file: &HashMap<&str, HashSet<String>>) -> Vec<String> {
    let (Some(claude), Some(agents)) = (bullets_by_file.get("CLAUDE.md"), bullets_by_file.get("AGENTS.md")) else {
        return Vec::new();
    };
    if claude.is_empty() || agents.is_empty() {
        return Vec::new();
    }
    let only_claude = claude.difference(agents).count();
    let only_agents = agents.difference(claude).count();
    if only_claude == 0 && only_agents == 0 {
        return Vec::new();
    }
    vec![trf!(
        "CLAUDE.md and AGENTS.md disagree: %d rules only for Claude, %d only for the other agents.",
        only_claude,
        only_agents
    )]
}

pub fn normalize(text: &str) -> String {
    text.to_lowercase().split(|c: char| !c.is_alphanumeric()).filter(|word| !word.is_empty()).collect::<Vec<_>>().join(" ")
}
