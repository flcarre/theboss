use std::collections::HashMap;
use std::path::{Path, PathBuf};

use chrono::Duration;
use serde_json::Value;

use crate::jsonl::{object_array, JsonlTail};
use crate::localization::tr;
use crate::models::{Harness, MessageRole, Timestamp, TokenUsage, TranscriptMessage, UserPrompt};
use crate::util::{day_key, modified, now, single_line, truncated};

pub const MESSAGE_LIMIT: usize = 400;
pub const DEFAULT_RECENT_WINDOW: f64 = 12.0 * 3600.0;
pub const TITLE_LIMIT: usize = 60;
pub const DETAIL_LIMIT: usize = 120;

#[derive(Debug, Clone, PartialEq)]
pub struct PendingTool {
    pub name: String,
    pub detail: String,
    pub since: Option<Timestamp>,
}

impl PendingTool {
    pub fn new(name: impl Into<String>, detail: &str, since: Option<Timestamp>) -> Self {
        PendingTool { name: name.into(), detail: truncated(&single_line(detail), DETAIL_LIMIT), since }
    }
}

#[derive(Debug, Clone)]
pub struct TranscriptState {
    pub keep_messages: bool,
    pub tail: JsonlTail,
    pub session_id: Option<String>,
    pub cwd: Option<String>,
    pub title: Option<String>,
    pub first_prompt: Option<String>,
    pub model: Option<String>,
    pub started_at: Option<Timestamp>,
    pub last_activity: Option<Timestamp>,
    pub tokens: TokenUsage,
    pub tokens_by_day: HashMap<String, TokenUsage>,
    pub usage_by_id: HashMap<String, TokenUsage>,
    pub prompts: Vec<UserPrompt>,
    pub messages: Vec<TranscriptMessage>,
    pub last_assistant_text: Option<String>,
    pub pending_tools: HashMap<String, PendingTool>,
    pub turn_started_at: Option<Timestamp>,
    pub turn_ended_at: Option<Timestamp>,
    pub approval_requested_at: Option<Timestamp>,
}

impl Default for TranscriptState {
    fn default() -> Self {
        TranscriptState::new(true)
    }
}

impl TranscriptState {
    pub fn new(keep_messages: bool) -> Self {
        TranscriptState {
            keep_messages,
            tail: JsonlTail::default(),
            session_id: None,
            cwd: None,
            title: None,
            first_prompt: None,
            model: None,
            started_at: None,
            last_activity: None,
            tokens: TokenUsage::default(),
            tokens_by_day: HashMap::new(),
            usage_by_id: HashMap::new(),
            prompts: Vec::new(),
            messages: Vec::new(),
            last_assistant_text: None,
            pending_tools: HashMap::new(),
            turn_started_at: None,
            turn_ended_at: None,
            approval_requested_at: None,
        }
    }

    pub fn reset(&mut self) {
        let tail = std::mem::take(&mut self.tail);
        *self = TranscriptState::new(self.keep_messages);
        self.tail = tail;
    }

    pub fn touch(&mut self, date: Option<Timestamp>) {
        let Some(date) = date else { return };
        if self.started_at.is_none_or(|started| date < started) {
            self.started_at = Some(date);
        }
        if self.last_activity.is_none_or(|last| date > last) {
            self.last_activity = Some(date);
        }
    }

    pub fn add_usage(&mut self, usage: TokenUsage, date: Option<Timestamp>) {
        self.tokens = self.tokens + usage;
        let entry = self.tokens_by_day.entry(day_key(date.unwrap_or_else(now))).or_default();
        *entry = *entry + usage;
    }

    pub fn append_message(&mut self, message: TranscriptMessage) {
        if !self.keep_messages {
            return;
        }
        self.messages.push(message);
        if self.messages.len() > MESSAGE_LIMIT {
            let excess = self.messages.len() - MESSAGE_LIMIT;
            self.messages.drain(..excess);
        }
    }

    pub fn record_prompt(&mut self, harness: Harness, text: &str, date: Option<Timestamp>) {
        let clean = text.trim();
        if clean.is_empty() {
            return;
        }
        if self.first_prompt.is_none() {
            self.first_prompt = Some(clean.to_string());
        }
        self.prompts.push(UserPrompt {
            harness,
            session_id: self.session_id.clone().unwrap_or_default(),
            cwd: self.cwd.clone().unwrap_or_default(),
            text: clean.to_string(),
            timestamp: date,
            previous_assistant: self.last_assistant_text.clone(),
        });
        self.append_message(TranscriptMessage { role: MessageRole::User, text: clean.to_string(), timestamp: date });
    }

    pub fn record_reply(&mut self, text: &str, date: Option<Timestamp>) {
        let clean = text.trim();
        if clean.is_empty() {
            return;
        }
        self.last_assistant_text = Some(clean.to_string());
        self.append_message(TranscriptMessage { role: MessageRole::Assistant, text: clean.to_string(), timestamp: date });
    }

    pub fn last_prompt(&self) -> Option<String> {
        self.prompts.last().map(|prompt| prompt.text.clone())
    }

    pub fn display_title(&self) -> String {
        if let Some(title) = self.title.as_ref().filter(|title| !title.is_empty()) {
            return title.clone();
        }
        if let Some(first) = &self.first_prompt {
            return truncated(&single_line(first), TITLE_LIMIT);
        }
        tr("Untitled session")
    }

    pub fn pending_description(&self) -> Option<String> {
        let pending = self.pending_tools.values().max_by(|a, b| a.since.cmp(&b.since))?;
        Some(if pending.detail.is_empty() { pending.name.clone() } else { format!("{} · {}", pending.name, pending.detail) })
    }
}

pub const DEFAULT_TEXT_TYPES: &[&str] = &["text", "input_text", "output_text"];

const NOISE_PREFIXES: &[&str] = &[
    "<local-command",
    "<system-reminder>",
    "Caveat:",
    "<environment_context>",
    "<user_instructions>",
    "# AGENTS.md",
    "<permissions",
    "<turn_aborted>",
    "<task-notification>",
    "<bash-",
    "[Request interrupted",
    "<user-prompt-submit-hook>",
    "<ci-monitor-event>",
    "<subagent_notification>",
];

const REMINDER_OPEN: &str = "<system-reminder>";
const REMINDER_CLOSE: &str = "</system-reminder>";

pub struct ContentText;

impl ContentText {
    pub fn extract(content: Option<&Value>, accepted_types: &[&str]) -> String {
        if let Some(text) = content.and_then(Value::as_str) {
            return text.to_string();
        }
        let Some(blocks) = object_array(content) else { return String::new() };
        blocks
            .iter()
            .filter(|block| block.get("type").and_then(Value::as_str).is_some_and(|kind| accepted_types.contains(&kind)))
            .filter_map(|block| block.get("text").and_then(Value::as_str))
            .collect::<Vec<_>>()
            .join("\n")
    }

    pub fn extract_default(content: Option<&Value>) -> String {
        Self::extract(content, DEFAULT_TEXT_TYPES)
    }

    pub fn clean_user_text(raw: &str) -> Option<String> {
        let mut text = raw.trim().to_string();
        if text.is_empty() {
            return None;
        }
        if text.contains("<command-name>") {
            let name = between(&text, "<command-name>", "</command-name>").unwrap_or_default();
            let args = between(&text, "<command-args>", "</command-args>").unwrap_or_default();
            let command = if name.starts_with('/') { name } else { format!("/{name}") };
            return Some(format!("{command} {args}").trim().to_string());
        }
        if NOISE_PREFIXES.iter().any(|prefix| text.starts_with(prefix)) {
            return None;
        }
        while let Some(start) = text.find(REMINDER_OPEN) {
            let after = start + REMINDER_OPEN.len();
            let Some(close) = text[after..].find(REMINDER_CLOSE) else { break };
            text.replace_range(start..after + close + REMINDER_CLOSE.len(), "");
        }
        let text = text.trim();
        (!text.is_empty()).then(|| text.to_string())
    }
}

fn between(text: &str, open: &str, close: &str) -> Option<String> {
    let start = text.find(open)? + open.len();
    let end = text[start..].find(close)? + start;
    Some(text[start..end].trim().to_string())
}

pub fn cutoff(window_secs: f64) -> Timestamp {
    now() - Duration::milliseconds((window_secs * 1000.0) as i64)
}

pub fn is_modified_since(path: &Path, cutoff: Option<Timestamp>) -> bool {
    match cutoff {
        None => true,
        Some(cutoff) => modified(path).is_some_and(|date| date >= cutoff),
    }
}

pub fn has_extension(path: &Path, extension: &str) -> bool {
    path.extension().is_some_and(|ext| ext == extension)
}

pub fn jsonl_files_under(dir: &Path, cutoff: Option<Timestamp>) -> Vec<PathBuf> {
    walkdir::WalkDir::new(dir)
        .into_iter()
        .filter_map(Result::ok)
        .map(walkdir::DirEntry::into_path)
        .filter(|path| has_extension(path, "jsonl") && is_modified_since(path, cutoff))
        .collect()
}

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub fn merge_days(into: &mut HashMap<String, TokenUsage>, days: &HashMap<String, TokenUsage>) {
    for (day, usage) in days {
        let entry = into.entry(day.clone()).or_default();
        *entry = *entry + *usage;
    }
}
