use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

use chrono::TimeZone;
use serde::{Deserialize, Serialize};

use crate::corrections::{self, Correction};
use crate::diff::{self, DiffLine};
use crate::localization::tr;
use crate::models::{AgentSession, Harness, Timestamp, UserPrompt};
use crate::paths::Paths;
use crate::rules::{self, GLOBAL_SCOPE};
use crate::trf;
use crate::util::{last_path_component, modified, now, single_line, trim_spaces, truncated};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SuggestionStatus {
    New,
    Applied,
    Dismissed,
    Saved,
}

impl SuggestionStatus {
    pub fn raw(self) -> &'static str {
        match self {
            SuggestionStatus::New => "new",
            SuggestionStatus::Applied => "applied",
            SuggestionStatus::Dismissed => "dismissed",
            SuggestionStatus::Saved => "saved",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SuggestionKind {
    LearnedRule,
    SetupFix,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum SuggestionOperation {
    AppendRule { rule: String },
    CreateFile { body: String },
    RemoveLines { lines: Vec<String> },
    AddFrontmatter { name: String, description: String },
}

impl SuggestionOperation {
    pub fn apply_to(&self, current: Option<&str>) -> String {
        let content = current.unwrap_or("");
        match self {
            SuggestionOperation::AppendRule { rule } => SuggestionEngine::appending(rule, content),
            SuggestionOperation::CreateFile { body } => {
                if content.is_empty() {
                    body.clone()
                } else {
                    content.to_string()
                }
            }
            SuggestionOperation::RemoveLines { lines } => {
                let remove: HashSet<&str> = lines.iter().map(String::as_str).collect();
                content.split('\n').filter(|line| !remove.contains(line)).collect::<Vec<_>>().join("\n")
            }
            SuggestionOperation::AddFrontmatter { name, description } => {
                if content.starts_with("---") {
                    content.to_string()
                } else {
                    format!("---\nname: {name}\ndescription: {description}\n---\n\n{content}")
                }
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Evidence {
    pub quote: String,
    pub context: Option<String>,
    pub harness: Harness,
    pub session_id: String,
    pub date: Option<Timestamp>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Suggestion {
    pub id: String,
    pub kind: SuggestionKind,
    pub title: String,
    pub rationale: String,
    pub project: String,
    pub file_path: String,
    pub operation: SuggestionOperation,
    pub evidence: Vec<Evidence>,
    pub status: SuggestionStatus,
    pub created_at: Timestamp,
    pub refined_rule: Option<String>,
}

impl Suggestion {
    pub fn refine(&mut self, rule: &str) {
        self.refined_rule = Some(rule.to_string());
        self.title = rule.to_string();
        if let SuggestionOperation::AppendRule { .. } = self.operation {
            self.operation = SuggestionOperation::AppendRule { rule: rule.to_string() };
        }
    }

    pub fn current_content(&self) -> Option<String> {
        std::fs::read_to_string(&self.file_path).ok()
    }

    pub fn proposed_content(&self) -> String {
        self.operation.apply_to(self.current_content().as_deref())
    }

    pub fn diff(&self) -> Vec<DiffLine> {
        let old = self.current_content().unwrap_or_default();
        diff::lines(&old, &self.proposed_content(), &self.display_path(), diff::DEFAULT_CONTEXT)
    }

    pub fn display_path(&self) -> String {
        let home = Paths::home().to_string_lossy().into_owned();
        match self.file_path.strip_prefix(&home) {
            Some(rest) if !home.is_empty() => format!("~{rest}"),
            _ => self.file_path.clone(),
        }
    }

    pub fn apply(&self) -> std::io::Result<()> {
        let new = self.proposed_content();
        let path = Path::new(&self.file_path);
        if let Some(parent) = path.parent().filter(|parent| !parent.as_os_str().is_empty()) {
            std::fs::create_dir_all(parent)?;
        }
        write_atomically(path, &new)
    }
}

pub fn write_atomically(path: &Path, content: &str) -> std::io::Result<()> {
    let name = path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
    let temporary = path.with_file_name(format!(".{name}.boss-{}", uuid::Uuid::new_v4().simple()));
    std::fs::write(&temporary, content)?;
    std::fs::rename(&temporary, path).inspect_err(|_| {
        let _ = std::fs::remove_file(&temporary);
    })
}

struct Cluster {
    project: String,
    harness: Harness,
    rule: String,
    items: Vec<Correction>,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct SuggestionEngine;

impl SuggestionEngine {
    pub const LEARNED_SECTIONS: [&'static str; 2] = ["## Learned rules", "## Règles apprises"];

    pub fn new() -> Self {
        SuggestionEngine
    }

    pub fn learned_section() -> String {
        tr("## Learned rules")
    }

    pub fn corrections(&self, prompts: &[UserPrompt]) -> Vec<Correction> {
        prompts.iter().filter_map(corrections::detect).collect()
    }

    pub fn suggestions(&self, prompts: &[UserPrompt], sessions: &[AgentSession]) -> Vec<Suggestion> {
        let mut result = self.learned_rules(&self.corrections(prompts));
        result.extend(self.setup_fixes(sessions));
        result
    }

    pub fn learned_rules(&self, corrections: &[Correction]) -> Vec<Suggestion> {
        let mut clusters: Vec<Cluster> = Vec::new();
        for correction in corrections {
            let Some(rule) = &correction.rule else { continue };
            let project = rules::project_root(&correction.prompt.cwd);
            match clusters
                .iter_mut()
                .find(|cluster| cluster.project == project && corrections::similarity(&cluster.rule, rule) >= 0.45)
            {
                Some(cluster) => cluster.items.push(correction.clone()),
                None => clusters.push(Cluster {
                    project,
                    harness: correction.prompt.harness,
                    rule: rule.clone(),
                    items: vec![correction.clone()],
                }),
            }
        }
        clusters.into_iter().filter_map(Self::learned_rule).collect()
    }

    fn learned_rule(cluster: Cluster) -> Option<Suggestion> {
        let target = Self::target_file(&cluster.project, cluster.harness);
        let existing = std::fs::read_to_string(&target).unwrap_or_default();
        if Self::already_covered(&cluster.rule, &existing) {
            return None;
        }
        let mut seen_quotes = HashSet::new();
        let unique: Vec<&Correction> =
            cluster.items.iter().filter(|item| seen_quotes.insert(item.prompt.text.to_lowercase())).collect();
        let evidence = unique
            .iter()
            .map(|item| Evidence {
                quote: truncated(&item.prompt.text, 400),
                context: item.prompt.previous_assistant.as_deref().map(|text| truncated(&single_line(text), 240)),
                harness: item.prompt.harness,
                session_id: item.prompt.session_id.clone(),
                date: item.prompt.timestamp,
            })
            .collect();
        let project_name =
            if cluster.project.is_empty() { GLOBAL_SCOPE.to_string() } else { last_path_component(&cluster.project) };
        let count = unique.len();
        let rationale = if count > 1 {
            trf!(
                "You corrected the agent %d times on this in %@. A written rule saves you from repeating it.",
                count,
                &project_name
            )
        } else {
            trf!("You corrected the agent on this in %@. A written rule keeps it from happening again.", &project_name)
        };
        Some(Suggestion {
            id: Self::stable_id(&["rule", &target, &cluster.rule]),
            kind: SuggestionKind::LearnedRule,
            title: cluster.rule.clone(),
            rationale,
            project: project_name,
            file_path: target,
            operation: SuggestionOperation::AppendRule { rule: cluster.rule.clone() },
            evidence,
            status: SuggestionStatus::New,
            created_at: cluster.items.iter().filter_map(|item| item.prompt.timestamp).max().unwrap_or_else(now),
            refined_rule: None,
        })
    }

    pub fn setup_fixes(&self, sessions: &[AgentSession]) -> Vec<Suggestion> {
        let mut result = Vec::new();
        let mut harnesses_by_project: BTreeMap<String, HashSet<Harness>> = BTreeMap::new();
        for session in sessions.iter().filter(|session| !session.cwd.is_empty()) {
            harnesses_by_project.entry(rules::project_root(&session.cwd)).or_default().insert(session.harness);
        }
        for (project, harnesses) in &harnesses_by_project {
            if !Path::new(project).exists() {
                continue;
            }
            let name = last_path_component(project);
            let claude_md = join(project, "CLAUDE.md");
            let agents_md = join(project, "AGENTS.md");
            let has_claude = Path::new(&claude_md).exists();
            let has_agents = Path::new(&agents_md).exists();
            if harnesses.contains(&Harness::Claude) && has_agents && !has_claude {
                result.push(Suggestion {
                    id: Self::stable_id(&["fix", &claude_md, "import-agents"]),
                    kind: SuggestionKind::SetupFix,
                    title: tr("Make Claude Code read AGENTS.md"),
                    rationale: trf!(
                        "%@ has an AGENTS.md but no CLAUDE.md: Claude Code does not read your rules in this project.",
                        &name
                    ),
                    project: name.clone(),
                    file_path: claude_md.clone(),
                    operation: SuggestionOperation::CreateFile { body: "@AGENTS.md\n".to_string() },
                    evidence: Vec::new(),
                    status: SuggestionStatus::New,
                    created_at: Self::stamp(&agents_md),
                    refined_rule: None,
                });
            }
            let other_agents =
                harnesses.contains(&Harness::Codex) || harnesses.contains(&Harness::Pi) || harnesses.contains(&Harness::Omp);
            if other_agents && has_claude && !has_agents {
                if let Ok(body) = std::fs::read_to_string(&claude_md) {
                    result.push(Suggestion {
                        id: Self::stable_id(&["fix", &agents_md, "mirror-claude"]),
                        kind: SuggestionKind::SetupFix,
                        title: tr("Share the CLAUDE.md rules with other agents"),
                        rationale: trf!(
                            "Codex and Pi read AGENTS.md, which %@ lacks: they work without the CLAUDE.md rules.",
                            &name
                        ),
                        project: name.clone(),
                        file_path: agents_md.clone(),
                        operation: SuggestionOperation::CreateFile { body },
                        evidence: Vec::new(),
                        status: SuggestionStatus::New,
                        created_at: Self::stamp(&claude_md),
                        refined_rule: None,
                    });
                }
            }
            let gemini_md = join(project, "GEMINI.md");
            if harnesses.contains(&Harness::Gemini) && has_agents && !Path::new(&gemini_md).exists() {
                result.push(Suggestion {
                    id: Self::stable_id(&["fix", &gemini_md, "import-agents"]),
                    kind: SuggestionKind::SetupFix,
                    title: tr("Make Gemini read AGENTS.md"),
                    rationale: trf!(
                        "%@ has an AGENTS.md but no GEMINI.md: Gemini CLI does not read your rules in this project.",
                        &name
                    ),
                    project: name.clone(),
                    file_path: gemini_md,
                    operation: SuggestionOperation::CreateFile { body: "@AGENTS.md\n".to_string() },
                    evidence: Vec::new(),
                    status: SuggestionStatus::New,
                    created_at: Self::stamp(&agents_md),
                    refined_rule: None,
                });
            }
            if has_claude {
                result.extend(self.broken_imports(&claude_md, &name));
            }
        }
        let global_claude = Paths::claude().join("CLAUDE.md").to_string_lossy().into_owned();
        result.extend(self.broken_imports(&global_claude, GLOBAL_SCOPE));
        for root in [Paths::claude().join("skills"), Paths::codex().join("skills")] {
            result.extend(self.skills_without_description(&root));
        }
        result
    }

    pub fn broken_imports(&self, file: &str, project: &str) -> Vec<Suggestion> {
        let Ok(content) = std::fs::read_to_string(file) else { return Vec::new() };
        let base = Path::new(file).parent().map(Path::to_path_buf).unwrap_or_default();
        let home = Paths::home().to_string_lossy().into_owned();
        let mut in_code = false;
        let mut broken: Vec<String> = Vec::new();
        for line in content.split('\n') {
            if line.starts_with("```") {
                in_code = !in_code;
            }
            let trimmed = trim_spaces(line);
            if in_code || !trimmed.starts_with('@') || trimmed.contains(' ') {
                continue;
            }
            let mut target = trimmed[1..].to_string();
            if let Some(rest) = target.strip_prefix("~/") {
                target = format!("{home}/{rest}");
            }
            let resolved =
                if target.starts_with('/') || Path::new(&target).is_absolute() { PathBuf::from(&target) } else { base.join(&target) };
            if !resolved.exists() {
                broken.push(line.to_string());
            }
        }
        if broken.is_empty() {
            return Vec::new();
        }
        let title = if broken.len() == 1 { tr("Remove a broken import") } else { trf!("Remove %d broken imports", broken.len()) };
        let listed = broken.iter().map(|line| trim_spaces(line)).collect::<Vec<_>>().join(", ");
        vec![Suggestion {
            id: Self::stable_id(&["fix", file, &broken.concat()]),
            kind: SuggestionKind::SetupFix,
            title,
            rationale: trf!(
                "%@ points to a file that no longer exists: the agent silently loses that part of its rules.",
                listed
            ),
            project: project.to_string(),
            file_path: file.to_string(),
            operation: SuggestionOperation::RemoveLines { lines: broken },
            evidence: Vec::new(),
            status: SuggestionStatus::New,
            created_at: Self::stamp(file),
            refined_rule: None,
        }]
    }

    pub fn skills_without_description(&self, root: &Path) -> Vec<Suggestion> {
        rules::sorted_entries(root)
            .into_iter()
            .filter_map(|entry| {
                let skill = rules::resolving_symlinks(&entry.join("SKILL.md"));
                let content = std::fs::read_to_string(&skill).ok()?;
                if content.starts_with("---") {
                    return None;
                }
                let entry_name = last_path_component(&entry.to_string_lossy());
                let heading = content
                    .split('\n')
                    .find(|line| line.starts_with('#'))
                    .map(|line| line.trim_matches(['#', ' ']).to_string())
                    .unwrap_or_else(|| entry_name.clone());
                let skill_path = skill.to_string_lossy().into_owned();
                Some(Suggestion {
                    id: Self::stable_id(&["fix", &skill_path, "frontmatter"]),
                    kind: SuggestionKind::SetupFix,
                    title: trf!("Describe the %@ skill", &entry_name),
                    rationale: tr("Without a name/description header, the agent does not know when to use this skill."),
                    project: GLOBAL_SCOPE.to_string(),
                    created_at: Self::stamp(&skill_path),
                    file_path: skill_path,
                    operation: SuggestionOperation::AddFrontmatter { name: entry_name, description: heading },
                    evidence: Vec::new(),
                    status: SuggestionStatus::New,
                    refined_rule: None,
                })
            })
            .collect()
    }

    pub fn distant_past() -> Timestamp {
        chrono::Utc.with_ymd_and_hms(1, 1, 1, 0, 0, 0).single().unwrap_or_default()
    }

    pub fn stamp(path: &str) -> Timestamp {
        modified(path).unwrap_or_else(Self::distant_past)
    }

    pub fn target_file(project: &str, harness: Harness) -> String {
        if project.is_empty() {
            let file = if harness == Harness::Claude { Paths::claude().join("CLAUDE.md") } else { Paths::codex().join("AGENTS.md") };
            return file.to_string_lossy().into_owned();
        }
        let claude = join(project, "CLAUDE.md");
        let agents = join(project, "AGENTS.md");
        if std::fs::read_to_string(&claude).is_ok_and(|content| content.contains("@AGENTS.md")) {
            return agents;
        }
        if harness == Harness::Claude {
            return claude;
        }
        if Path::new(&agents).exists() || !Path::new(&claude).exists() {
            return agents;
        }
        claude
    }

    pub fn already_covered(rule: &str, content: &str) -> bool {
        content.split('\n').any(|line| corrections::similarity(line, rule) >= 0.6)
    }

    pub fn appending(rule: &str, content: &str) -> String {
        let bullet = format!("- {rule}");
        let mut lines: Vec<String> =
            if content.is_empty() { Vec::new() } else { content.split('\n').map(str::to_string).collect() };
        while lines.last().is_some_and(String::is_empty) {
            lines.pop();
        }
        if let Some(header) = lines.iter().position(|line| Self::LEARNED_SECTIONS.contains(&line.as_str())) {
            let mut insert = header + 1;
            while insert < lines.len() && !lines[insert].starts_with('#') {
                insert += 1;
            }
            while insert > header + 1 && lines[insert - 1].is_empty() {
                insert -= 1;
            }
            lines.insert(insert, bullet);
        } else {
            if !lines.is_empty() {
                lines.push(String::new());
            }
            lines.push(Self::learned_section());
            lines.push(String::new());
            lines.push(bullet);
        }
        lines.join("\n") + "\n"
    }

    pub fn stable_id(parts: &[&str]) -> String {
        let mut hash: u64 = 1469598103934665603;
        for byte in parts.join("|").bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(1099511628211);
        }
        format!("{hash:x}")
    }
}

fn join(base: &str, name: &str) -> String {
    Path::new(base).join(name).to_string_lossy().into_owned()
}
