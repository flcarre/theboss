use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::jsonl::{int_or_zero, object_array, object_field, string_array, JsonlTail};
use crate::localization::tr;
use crate::models::{AgentSession, AgentStatus, Harness, MessageRole, Timestamp, TokenUsage, TranscriptMessage, UserPrompt};
use crate::paths::Paths;
use crate::transcript::{cutoff, has_extension, is_modified_since, path_string, ContentText, DEFAULT_RECENT_WINDOW, TITLE_LIMIT};
use crate::util::{day_key, modified, now, parse_date, seconds_since, single_line, truncated};

const LIVE_WINDOW: f64 = 600.0;
const USER: &str = "user";
const GEMINI: &str = "gemini";

#[derive(Debug, Clone, PartialEq)]
pub struct GeminiMessage {
    pub id: String,
    pub kind: String,
    pub text: String,
    pub is_tool_result: bool,
    pub has_tool_calls: bool,
    pub timestamp: Option<Timestamp>,
    pub model: Option<String>,
    pub tokens: Option<TokenUsage>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct GeminiSession {
    pub session_id: Option<String>,
    pub summary: Option<String>,
    pub start_time: Option<Timestamp>,
    pub last_updated: Option<Timestamp>,
    pub order: Vec<String>,
    pub messages: HashMap<String, GeminiMessage>,
}

impl GeminiSession {
    pub fn ordered(&self) -> Vec<&GeminiMessage> {
        self.order.iter().filter_map(|id| self.messages.get(id)).collect()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct GeminiFile {
    pub path: PathBuf,
    pub cwd: String,
}

pub struct GeminiSource {
    cache: HashMap<PathBuf, (u64, GeminiSession)>,
    recent_window: f64,
}

impl Default for GeminiSource {
    fn default() -> Self {
        GeminiSource::new(DEFAULT_RECENT_WINDOW)
    }
}

impl GeminiSource {
    pub fn new(recent_window: f64) -> Self {
        GeminiSource { cache: HashMap::new(), recent_window }
    }

    pub fn root(&self) -> PathBuf {
        match std::env::var_os("GEMINI_CLI_HOME") {
            Some(custom) if !Paths::is_sandboxed() => PathBuf::from(custom).join(".gemini"),
            _ => Paths::gemini(),
        }
    }

    pub fn session_files(&self, window_secs: f64) -> Vec<GeminiFile> {
        let root = self.root();
        let Ok(projects) = std::fs::read_dir(root.join("tmp")) else { return Vec::new() };
        let cutoff = Some(cutoff(window_secs));
        let registry = self.project_registry();
        let mut result = Vec::new();
        for project in projects.filter_map(Result::ok).map(|entry| entry.path()) {
            let Ok(files) = std::fs::read_dir(project.join("chats")) else { continue };
            let marker = std::fs::read_to_string(project.join(".project_root")).ok().map(|text| text.trim().to_string());
            let slug = project.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
            let cwd = marker.or_else(|| registry.get(&slug).cloned()).unwrap_or_default();
            for file in files.filter_map(Result::ok).map(|entry| entry.path()) {
                let is_session = file.file_name().is_some_and(|name| name.to_string_lossy().starts_with("session-"));
                if has_extension(&file, "jsonl") && is_session && is_modified_since(&file, cutoff) {
                    result.push(GeminiFile { path: file, cwd: cwd.clone() });
                }
            }
        }
        result
    }

    pub fn project_registry(&self) -> HashMap<String, String> {
        let Ok(data) = std::fs::read(self.root().join("projects.json")) else { return HashMap::new() };
        let Ok(json) = serde_json::from_slice::<Value>(&data) else { return HashMap::new() };
        let Some(projects) = json.get("projects").and_then(Value::as_object) else { return HashMap::new() };
        let mut by_slug = HashMap::new();
        for (path, slug) in projects {
            let Some(slug) = slug.as_str() else { return HashMap::new() };
            by_slug.insert(slug.to_string(), path.clone());
        }
        by_slug
    }

    pub fn parse(&mut self, path: &Path) -> &GeminiSession {
        let size = std::fs::metadata(path).map(|metadata| metadata.len()).unwrap_or(0);
        let key = path.to_path_buf();
        let fresh = self.cache.get(&key).is_some_and(|(cached_size, _)| *cached_size == size);
        if !fresh {
            let mut session = GeminiSession::default();
            let mut tail = JsonlTail::default();
            for object in tail.read_new_objects(path).0 {
                Self::consume(&object, &mut session);
            }
            self.cache.insert(key.clone(), (size, session));
        }
        &self.cache[&key].1
    }

    pub fn consume(object: &Value, session: &mut GeminiSession) {
        if let (Some(id), Some(_)) = (object.get("sessionId").and_then(Value::as_str), object.get("projectHash")) {
            session.session_id = Some(id.to_string());
            session.start_time = parse_date(object.get("startTime"));
            session.last_updated = parse_date(object.get("lastUpdated"));
            if let Some(summary) = object.get("summary").and_then(Value::as_str) {
                session.summary = Some(summary.to_string());
            }
            return;
        }
        if let Some(set) = object_field(object, "$set") {
            if let Some(updated) = parse_date(set.get("lastUpdated")) {
                session.last_updated = Some(updated);
            }
            if let Some(summary) = set.get("summary").and_then(Value::as_str).filter(|s| !s.is_empty()) {
                session.summary = Some(summary.to_string());
            }
            if let Some(id) = set.get("sessionId").and_then(Value::as_str) {
                session.session_id = Some(id.to_string());
            }
            return;
        }
        if let Some(rewind) = object.get("$rewindTo").and_then(Value::as_str) {
            if let Some(index) = session.order.iter().position(|id| id == rewind) {
                for id in session.order.drain(index..) {
                    session.messages.remove(&id);
                }
            }
            return;
        }
        if let Some(patch) = object_field(object, "$patch") {
            Self::apply_patch(patch, session);
            return;
        }
        let (Some(id), Some(kind)) =
            (object.get("id").and_then(Value::as_str), object.get("type").and_then(Value::as_str))
        else {
            return;
        };
        let content = object.get("content");
        let tokens = object_field(object, "tokens").map(|usage| {
            let cached = int_or_zero(usage, "cached");
            TokenUsage::new(
                (int_or_zero(usage, "input") - cached).max(0),
                int_or_zero(usage, "output") + int_or_zero(usage, "thoughts"),
                cached,
                0,
            )
        });
        let message = GeminiMessage {
            id: id.to_string(),
            kind: kind.to_string(),
            text: Self::text_of(content),
            is_tool_result: Self::is_tool_result(content),
            has_tool_calls: object.get("toolCalls").and_then(Value::as_array).is_some_and(|calls| !calls.is_empty()),
            timestamp: parse_date(object.get("timestamp")),
            model: object.get("model").and_then(Value::as_str).map(str::to_string),
            tokens,
        };
        if !session.messages.contains_key(id) {
            session.order.push(id.to_string());
        }
        session.messages.insert(id.to_string(), message);
    }

    fn apply_patch(patch: &Value, session: &mut GeminiSession) {
        for id in string_array(patch.get("removeIds")).unwrap_or_default() {
            session.messages.remove(id);
            session.order.retain(|existing| existing != id);
        }
        if let (Some(id), Some(content)) = (patch.get("id").and_then(Value::as_str), patch.get("content")) {
            if let Some(message) = session.messages.get_mut(id) {
                message.text = Self::text_of(Some(content));
            }
        }
        if let Some(order_ids) = string_array(patch.get("orderIds")) {
            let proposed: HashSet<&str> = order_ids.iter().copied().collect();
            let current: HashSet<&str> = session.order.iter().map(String::as_str).collect();
            if proposed == current {
                session.order = order_ids.into_iter().map(str::to_string).collect();
            }
        }
    }

    pub fn text_of(content: Option<&Value>) -> String {
        let Some(content) = content else { return String::new() };
        if let Some(text) = content.as_str() {
            return text.to_string();
        }
        if let Some(parts) = object_array(Some(content)) {
            return parts.iter().filter_map(|part| part.get("text").and_then(Value::as_str)).collect::<Vec<_>>().join("\n");
        }
        if content.is_object() {
            return content.get("text").and_then(Value::as_str).unwrap_or_default().to_string();
        }
        String::new()
    }

    pub fn is_tool_result(content: Option<&Value>) -> bool {
        object_array(content).is_some_and(|parts| parts.iter().any(|part| part.get("functionResponse").is_some()))
    }

    pub fn status(session: &GeminiSession, modified: Timestamp) -> AgentStatus {
        let idle = seconds_since(modified);
        let ordered = session.ordered();
        let Some(last) = ordered.iter().rev().find(|message| message.kind == USER || message.kind == GEMINI) else {
            return AgentStatus::Finished;
        };
        if last.kind == USER {
            return if idle < LIVE_WINDOW { AgentStatus::Working } else { AgentStatus::Finished };
        }
        if last.text.trim().is_empty() && !last.has_tool_calls {
            if idle < 20.0 {
                return AgentStatus::Working;
            }
            return if idle < 3600.0 { AgentStatus::NeedsApproval } else { AgentStatus::Finished };
        }
        if idle < 10.0 {
            AgentStatus::Working
        } else {
            AgentStatus::Finished
        }
    }

    pub fn sessions(&mut self) -> Vec<AgentSession> {
        let mut result = Vec::new();
        for file in self.session_files(self.recent_window) {
            let session = self.parse(&file.path);
            let prompts = Self::prompts(session, &file.cwd);
            let Some(id) = session.session_id.clone() else { continue };
            if prompts.is_empty() {
                continue;
            }
            let modified = modified(&file.path).unwrap_or_else(now);
            let status = Self::status(session, modified);
            let ordered = session.ordered();
            let title = session
                .summary
                .clone()
                .or_else(|| prompts.first().map(|prompt| truncated(&single_line(&prompt.text), TITLE_LIMIT)))
                .unwrap_or_else(|| tr("Untitled session"));
            let mut agent = AgentSession::new(Harness::Gemini, id, title, file.cwd.clone(), status, modified);
            agent.started_at = session.start_time;
            agent.last_prompt = prompts.last().map(|prompt| prompt.text.clone());
            agent.last_reply = ordered
                .iter()
                .rev()
                .find(|message| message.kind == GEMINI && !message.text.is_empty())
                .map(|message| message.text.clone());
            agent.pending_action = (status == AgentStatus::NeedsApproval)
                .then(|| tr("A tool call is waiting for your confirmation"));
            agent.model = ordered.iter().rev().find_map(|message| message.model.clone());
            agent.tokens = ordered.iter().filter_map(|message| message.tokens).sum();
            agent.prompt_count = prompts.len() as i64;
            agent.transcript_path = Some(path_string(&file.path));
            agent.is_live = seconds_since(modified) < LIVE_WINDOW;
            result.push(agent);
        }
        result
    }

    pub fn prompts(session: &GeminiSession, cwd: &str) -> Vec<UserPrompt> {
        let mut previous: Option<String> = None;
        let mut result = Vec::new();
        for message in session.ordered() {
            if message.kind == GEMINI && !message.text.is_empty() {
                previous = Some(message.text.clone());
            }
            if message.kind != USER || message.is_tool_result {
                continue;
            }
            let Some(text) = ContentText::clean_user_text(&message.text) else { continue };
            result.push(UserPrompt {
                harness: Harness::Gemini,
                session_id: session.session_id.clone().unwrap_or_default(),
                cwd: cwd.to_string(),
                text,
                timestamp: message.timestamp,
                previous_assistant: previous.clone(),
            });
        }
        result
    }

    pub fn messages(&mut self, path: &Path) -> Vec<TranscriptMessage> {
        self.parse(path)
            .ordered()
            .into_iter()
            .filter_map(|message| {
                let role = match message.kind.as_str() {
                    USER if !message.is_tool_result && !message.text.is_empty() => MessageRole::User,
                    GEMINI if !message.text.is_empty() => MessageRole::Assistant,
                    _ => return None,
                };
                Some(TranscriptMessage { role, text: message.text.clone(), timestamp: message.timestamp })
            })
            .collect()
    }

    pub fn all_prompts(&mut self, window_secs: f64) -> Vec<UserPrompt> {
        let files = self.session_files(window_secs);
        files.iter().flat_map(|file| Self::prompts(self.parse(&file.path), &file.cwd)).collect()
    }

    pub fn tokens_by_day(&mut self, window_secs: f64) -> HashMap<String, TokenUsage> {
        let mut result: HashMap<String, TokenUsage> = HashMap::new();
        for file in self.session_files(window_secs) {
            for message in self.parse(&file.path).ordered() {
                let Some(tokens) = message.tokens else { continue };
                let entry = result.entry(day_key(message.timestamp.unwrap_or_else(now))).or_default();
                *entry = *entry + tokens;
            }
        }
        result
    }
}
