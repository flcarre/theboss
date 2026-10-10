use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::jsonl::{int_or_zero, object_array, object_field};
use crate::models::{AgentSession, AgentStatus, Harness, Timestamp, TokenUsage, TranscriptMessage, UserPrompt};
use crate::paths::Paths;
use crate::transcript::{
    cutoff, is_modified_since, merge_days, path_string, ContentText, PendingTool, TranscriptState, DEFAULT_RECENT_WINDOW,
    DETAIL_LIMIT,
};
use crate::util::{is_process_alive, modified, now, parse_date, seconds_since, single_line, truncated};

const EVENTS_FILE: &str = "events.jsonl";
const WORKSPACE_FILE: &str = "workspace.yaml";
const LOCK_PREFIX: &str = "inuse.";
const LOCK_SUFFIX: &str = ".lock";
const PERMISSION: &str = "permission";

pub struct CopilotSource {
    states: HashMap<PathBuf, TranscriptState>,
    permissions: HashMap<PathBuf, HashMap<String, String>>,
    finished_turn: HashMap<PathBuf, bool>,
    recent_window: f64,
    pub keep_messages: bool,
}

impl Default for CopilotSource {
    fn default() -> Self {
        CopilotSource::new(DEFAULT_RECENT_WINDOW)
    }
}

impl CopilotSource {
    pub fn new(recent_window: f64) -> Self {
        CopilotSource {
            states: HashMap::new(),
            permissions: HashMap::new(),
            finished_turn: HashMap::new(),
            recent_window,
            keep_messages: true,
        }
    }

    pub fn root(&self) -> PathBuf {
        match std::env::var_os("COPILOT_HOME") {
            Some(custom) if !Paths::is_sandboxed() => PathBuf::from(custom),
            _ => Paths::copilot(),
        }
    }

    pub fn session_directories(&self, window_secs: f64) -> Vec<PathBuf> {
        let Ok(entries) = std::fs::read_dir(self.root().join("session-state")) else { return Vec::new() };
        let cutoff = Some(cutoff(window_secs));
        entries
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|dir| {
                let events = dir.join(EVENTS_FILE);
                modified(&events).is_some() && is_modified_since(&events, cutoff)
            })
            .collect()
    }

    pub fn workspace(dir: &Path) -> HashMap<String, String> {
        let Ok(text) = std::fs::read_to_string(dir.join(WORKSPACE_FILE)) else { return HashMap::new() };
        let mut result = HashMap::new();
        for line in text.split('\n').filter(|line| !line.is_empty()) {
            if line.starts_with(' ') || line.starts_with('-') {
                continue;
            }
            let Some((key, value)) = line.split_once(':') else { continue };
            let key = key.trim().to_string();
            let mut value = value.trim();
            for quote in ['"', '\''] {
                if value.len() >= 2 && value.starts_with(quote) && value.ends_with(quote) {
                    value = &value[1..value.len() - 1];
                }
            }
            result.insert(key, value.to_string());
        }
        result
    }

    pub fn live_pid(dir: &Path) -> Option<u32> {
        let entries = std::fs::read_dir(dir).ok()?;
        entries.filter_map(Result::ok).find_map(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            let pid: u32 = name.strip_prefix(LOCK_PREFIX)?.strip_suffix(LOCK_SUFFIX)?.parse().ok()?;
            is_process_alive(pid).then_some(pid)
        })
    }

    pub fn sessions(&mut self) -> Vec<AgentSession> {
        let mut result = Vec::new();
        for dir in self.session_directories(self.recent_window) {
            let path = dir.join(EVENTS_FILE);
            self.parse(&path);
            let Some(state) = self.states.get(&path) else { continue };
            if state.prompts.is_empty() {
                continue;
            }
            let workspace = Self::workspace(&dir);
            let modified = modified(&path).unwrap_or_else(now);
            let pid = Self::live_pid(&dir);
            let pending = self.permissions.get(&path).cloned().unwrap_or_default();
            let finished = self.finished_turn.get(&path).copied() == Some(true);
            let status = if pid.is_some() && !pending.is_empty() {
                AgentStatus::NeedsApproval
            } else if (pid.is_some() || seconds_since(modified) < 10.0) && !finished {
                AgentStatus::Working
            } else {
                AgentStatus::Finished
            };
            let id = state
                .session_id
                .clone()
                .or_else(|| workspace.get("id").cloned())
                .unwrap_or_else(|| dir.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default());
            let title = workspace
                .get("summary")
                .filter(|summary| !summary.is_empty())
                .cloned()
                .unwrap_or_else(|| state.display_title());
            let cwd = state.cwd.clone().or_else(|| workspace.get("cwd").cloned()).unwrap_or_default();
            let mut session = AgentSession::new(Harness::Copilot, id, title, cwd, status, modified);
            session.started_at = state.started_at;
            session.last_prompt = state.last_prompt();
            session.last_reply = state.last_assistant_text.clone();
            session.pending_action = if status == AgentStatus::NeedsApproval { pending.values().min().cloned() } else { None };
            session.model = state.model.clone();
            session.tokens = state.tokens;
            session.prompt_count = state.prompts.len() as i64;
            session.pid = pid;
            session.transcript_path = Some(path_string(&path));
            session.is_live = pid.is_some();
            result.push(session);
        }
        result
    }

    pub fn parse(&mut self, path: &Path) -> &TranscriptState {
        let key = path.to_path_buf();
        let mut state = self.states.remove(&key).unwrap_or_else(|| TranscriptState::new(self.keep_messages));
        let (objects, reset) = state.tail.read_new_objects(path);
        if reset {
            state.reset();
            self.permissions.insert(key.clone(), HashMap::new());
            self.finished_turn.remove(&key);
        }
        for object in &objects {
            self.consume(object, &key, &mut state);
        }
        self.states.entry(key).insert_entry(state).into_mut()
    }

    fn set_finished(&mut self, path: &Path, finished: bool) {
        self.finished_turn.insert(path.to_path_buf(), finished);
    }

    fn consume(&mut self, object: &Value, path: &Path, state: &mut TranscriptState) {
        let date = parse_date(object.get("timestamp"));
        let empty = Value::Object(Default::default());
        let data = object_field(object, "data").unwrap_or(&empty);
        let text = |key: &str| data.get(key).and_then(Value::as_str);
        state.touch(date);
        match object.get("type").and_then(Value::as_str) {
            Some("session.start" | "session.resume") => {
                if let Some(id) = text("sessionId") {
                    state.session_id = Some(id.to_string());
                }
                if let Some(cwd) = object_field(data, "context").and_then(|context| context.get("cwd")).and_then(Value::as_str) {
                    state.cwd = Some(cwd.to_string());
                }
                if let Some(model) = text("selectedModel") {
                    state.model = Some(model.to_string());
                }
            }
            Some("session.context_changed") => {
                let from_context = object_field(data, "context").and_then(|context| context.get("cwd")).and_then(Value::as_str);
                if let Some(cwd) = from_context.or_else(|| text("cwd")) {
                    state.cwd = Some(cwd.to_string());
                }
            }
            Some("session.model_change") => {
                if let Some(model) = text("newModel") {
                    state.model = Some(model.to_string());
                }
            }
            Some("user.message") => {
                if object.get("agentId").is_some() {
                    return;
                }
                let Some(clean) = text("content").and_then(ContentText::clean_user_text) else { return };
                state.record_prompt(Harness::Copilot, &clean, date);
                self.set_finished(path, false);
            }
            Some("assistant.turn_start") => self.set_finished(path, false),
            Some("assistant.message") => {
                if object.get("agentId").is_some() || data.get("parentToolCallId").is_some() {
                    return;
                }
                if let Some(model) = text("model") {
                    state.model = Some(model.to_string());
                }
                let has_requests = object_array(data.get("toolRequests")).is_some_and(|requests| !requests.is_empty());
                if let Some(content) = text("content").filter(|content| !content.is_empty()) {
                    state.record_reply(content, date);
                }
                self.set_finished(path, !has_requests);
            }
            Some("tool.execution_start") => {
                if let Some(id) = text("toolCallId") {
                    let tool = PendingTool::new(text("toolName").unwrap_or("tool"), text("toolTitle").unwrap_or(""), date);
                    state.pending_tools.insert(id.to_string(), tool);
                }
                self.set_finished(path, false);
            }
            Some("tool.execution_complete") => {
                if let Some(id) = text("toolCallId") {
                    state.pending_tools.remove(id);
                }
            }
            Some("permission.requested") => self.record_permission(data, path),
            Some("permission.completed") => {
                if let Some(id) = text("requestId") {
                    if let Some(pending) = self.permissions.get_mut(path) {
                        pending.remove(id);
                    }
                }
            }
            Some("abort" | "session.task_complete" | "session.shutdown") => {
                self.set_finished(path, true);
                self.permissions.insert(path.to_path_buf(), HashMap::new());
                state.pending_tools.clear();
                Self::record_model_metrics(data, date, state);
            }
            _ => {}
        }
    }

    fn record_permission(&mut self, data: &Value, path: &Path) {
        let Some(id) = data.get("requestId").and_then(Value::as_str) else { return };
        let empty = Value::Object(Default::default());
        let request = object_field(data, "permissionRequest").unwrap_or(&empty);
        let field = |key: &str| request.get(key).and_then(Value::as_str);
        let detail = ["fullCommandText", "fileName", "url", "toolName", "path", "kind"]
            .into_iter()
            .find_map(field)
            .unwrap_or(PERMISSION);
        let description = format!("{} · {}", field("kind").unwrap_or(PERMISSION), truncated(&single_line(detail), DETAIL_LIMIT));
        self.permissions.entry(path.to_path_buf()).or_default().insert(id.to_string(), description);
    }

    fn record_model_metrics(data: &Value, date: Option<Timestamp>, state: &mut TranscriptState) {
        let Some(metrics) = data.get("modelMetrics").and_then(Value::as_object) else { return };
        for model in metrics.values().filter(|model| model.is_object()) {
            let Some(usage) = object_field(model, "usage") else { continue };
            let cache_read = int_or_zero(usage, "cacheReadTokens");
            state.add_usage(
                TokenUsage::new(
                    (int_or_zero(usage, "inputTokens") - cache_read).max(0),
                    int_or_zero(usage, "outputTokens") + int_or_zero(usage, "reasoningTokens"),
                    cache_read,
                    int_or_zero(usage, "cacheWriteTokens"),
                ),
                date,
            );
        }
    }

    pub fn messages(&mut self, path: &Path) -> Vec<TranscriptMessage> {
        self.parse(path).messages.clone()
    }

    pub fn all_prompts(&mut self, window_secs: f64) -> Vec<UserPrompt> {
        let dirs = self.session_directories(window_secs);
        dirs.iter().flat_map(|dir| self.parse(&dir.join(EVENTS_FILE)).prompts.clone()).collect()
    }

    pub fn tokens_by_day(&mut self, window_secs: f64) -> HashMap<String, TokenUsage> {
        let mut result = HashMap::new();
        for dir in self.session_directories(window_secs) {
            merge_days(&mut result, &self.parse(&dir.join(EVENTS_FILE)).tokens_by_day);
        }
        result
    }
}
