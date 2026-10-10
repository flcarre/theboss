use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::jsonl::{int_or_zero, json_int, object_field};
use crate::localization::tr;
use crate::models::{
    AgentSession, AgentStatus, CodexRateSnapshot, Harness, MessageRole, RateWindow, Timestamp, TokenUsage,
    TranscriptMessage, UserPrompt,
};
use crate::paths::Paths;
use crate::transcript::{
    cutoff, jsonl_files_under, merge_days, path_string, ContentText, PendingTool, TranscriptState, DEFAULT_RECENT_WINDOW,
};
use crate::trf;
use crate::util::{modified, now, parse_date, seconds_since};

pub const APPROVAL_TOOLS: &[&str] = &["request_user_input", "request_user_input_async", "ask_user", "request_permissions"];
const RATE_LIMIT_LOOKBACK: f64 = 3.0 * 24.0 * 3600.0;
const LIVE_WINDOW: f64 = 600.0;
const MINUTES_PER_DAY: i64 = 24 * 60;
const MINUTES_PER_WEEK: i64 = 7 * MINUTES_PER_DAY;

pub struct CodexSource {
    states: HashMap<PathBuf, TranscriptState>,
    event_prompts: HashMap<PathBuf, bool>,
    last_totals: HashMap<PathBuf, TokenUsage>,
    rate_snapshots: HashMap<PathBuf, CodexRateSnapshot>,
    recent_window: f64,
    pub keep_messages: bool,
}

impl Default for CodexSource {
    fn default() -> Self {
        CodexSource::new(DEFAULT_RECENT_WINDOW)
    }
}

impl CodexSource {
    pub fn new(recent_window: f64) -> Self {
        CodexSource {
            states: HashMap::new(),
            event_prompts: HashMap::new(),
            last_totals: HashMap::new(),
            rate_snapshots: HashMap::new(),
            recent_window,
            keep_messages: true,
        }
    }

    pub fn sessions_dir(&self) -> PathBuf {
        Paths::codex().join("sessions")
    }

    pub fn rollout_files(&self, window_secs: Option<f64>) -> Vec<PathBuf> {
        jsonl_files_under(&self.sessions_dir(), window_secs.map(cutoff))
    }

    pub fn thread_names(&self) -> HashMap<String, String> {
        let Ok(content) = std::fs::read_to_string(Paths::codex().join("session_index.jsonl")) else {
            return HashMap::new();
        };
        content
            .split('\n')
            .filter(|line| !line.is_empty())
            .filter_map(|line| serde_json::from_str::<Value>(line).ok())
            .filter_map(|json| {
                let id = json.get("id")?.as_str()?.to_string();
                let name = json.get("thread_name")?.as_str()?.to_string();
                Some((id, name))
            })
            .collect()
    }

    pub fn sessions(&mut self) -> Vec<AgentSession> {
        let names = self.thread_names();
        let files = self.rollout_files(Some(self.recent_window));
        let mut result = Vec::new();
        for path in files {
            let state = self.parse(&path);
            let Some(id) = state.session_id.clone() else { continue };
            if state.prompts.is_empty() {
                continue;
            }
            let modified = modified(&path).unwrap_or_else(now);
            let status = Self::status(state, modified);
            let title = names.get(&id).cloned().unwrap_or_else(|| state.display_title());
            let mut session =
                AgentSession::new(Harness::Codex, id, title, state.cwd.clone().unwrap_or_default(), status, modified);
            session.started_at = state.started_at;
            session.last_prompt = state.last_prompt();
            session.last_reply = state.last_assistant_text.clone();
            session.pending_action = if status == AgentStatus::NeedsApproval { state.pending_description() } else { None };
            session.model = state.model.clone();
            session.tokens = state.tokens;
            session.prompt_count = state.prompts.len() as i64;
            session.transcript_path = Some(path_string(&path));
            session.is_live = seconds_since(modified) < LIVE_WINDOW;
            result.push(session);
        }
        result
    }

    pub fn status(state: &TranscriptState, modified: Timestamp) -> AgentStatus {
        let idle = seconds_since(modified);
        let turn_open = state
            .turn_started_at
            .is_some_and(|start| state.turn_ended_at.is_none_or(|end| end < start));
        if turn_open {
            if let Some(asked) = state.approval_requested_at {
                if state.turn_started_at.is_none_or(|start| asked >= start) {
                    return AgentStatus::NeedsApproval;
                }
            }
        }
        if turn_open && state.pending_tools.values().any(|tool| APPROVAL_TOOLS.contains(&tool.name.as_str())) {
            return AgentStatus::NeedsApproval;
        }
        if turn_open && idle < LIVE_WINDOW {
            return AgentStatus::Working;
        }
        if idle < 10.0 {
            return AgentStatus::Working;
        }
        AgentStatus::Finished
    }

    pub fn latest_rate_limits(&mut self) -> Option<CodexRateSnapshot> {
        for path in self.rollout_files(Some(RATE_LIMIT_LOOKBACK)) {
            self.parse(&path);
        }
        self.rate_snapshots.values().max_by(|a, b| a.observed_at.cmp(&b.observed_at)).cloned()
    }

    pub fn messages(&self, session_id: &str) -> Vec<TranscriptMessage> {
        self.states
            .values()
            .find(|state| state.session_id.as_deref() == Some(session_id))
            .map(|state| state.messages.clone())
            .unwrap_or_default()
    }

    pub fn all_prompts(&mut self, window_secs: f64) -> Vec<UserPrompt> {
        let files = self.rollout_files(Some(window_secs));
        files.iter().flat_map(|file| self.parse(file).prompts.clone()).collect()
    }

    pub fn tokens_by_day(&mut self, window_secs: f64) -> HashMap<String, TokenUsage> {
        let mut result = HashMap::new();
        for file in self.rollout_files(Some(window_secs)) {
            merge_days(&mut result, &self.parse(&file).tokens_by_day);
        }
        result
    }

    pub fn parse(&mut self, path: &Path) -> &TranscriptState {
        let key = path.to_path_buf();
        let mut state = self.states.remove(&key).unwrap_or_else(|| TranscriptState::new(self.keep_messages));
        let (objects, reset) = state.tail.read_new_objects(path);
        if reset {
            state.reset();
            self.event_prompts.insert(key.clone(), false);
            self.last_totals.remove(&key);
        }
        for object in &objects {
            self.consume(object, &key, &mut state);
        }
        self.states.entry(key).insert_entry(state).into_mut()
    }

    fn consume(&mut self, object: &Value, path: &Path, state: &mut TranscriptState) {
        let date = parse_date(object.get("timestamp"));
        let Some(payload) = object_field(object, "payload") else { return };
        let payload_type = payload.get("type").and_then(Value::as_str);
        match object.get("type").and_then(Value::as_str) {
            Some("session_meta") => {
                state.session_id = payload
                    .get("id")
                    .and_then(Value::as_str)
                    .or_else(|| payload.get("session_id").and_then(Value::as_str))
                    .map(str::to_string);
                state.cwd = payload.get("cwd").and_then(Value::as_str).map(str::to_string);
                state.touch(parse_date(payload.get("timestamp")).or(date));
            }
            Some("turn_context") => {
                if let Some(model) = payload.get("model").and_then(Value::as_str) {
                    state.model = Some(model.to_string());
                }
            }
            Some("response_item") => {
                state.touch(date);
                self.consume_response_item(payload, payload_type, date, path, state);
            }
            Some("event_msg") => {
                state.touch(date);
                self.consume_event(payload, payload_type, date, path, state);
            }
            _ => {}
        }
    }

    fn uses_event_prompts(&self, path: &Path) -> bool {
        self.event_prompts.get(path).copied() == Some(true)
    }

    fn consume_response_item(
        &mut self,
        payload: &Value,
        payload_type: Option<&str>,
        date: Option<Timestamp>,
        path: &Path,
        state: &mut TranscriptState,
    ) {
        let text_field = |key: &str| payload.get(key).and_then(Value::as_str);
        match payload_type {
            Some("message") => {
                let role = text_field("role");
                let text = ContentText::extract_default(payload.get("content"));
                if role == Some("user") && !self.uses_event_prompts(path) {
                    if let Some(clean) = ContentText::clean_user_text(&text) {
                        state.record_prompt(Harness::Codex, &clean, date);
                        return;
                    }
                }
                if role == Some("assistant") {
                    state.record_reply(&text, date);
                }
            }
            Some("function_call" | "custom_tool_call" | "local_shell_call") => {
                let id = text_field("call_id")
                    .or_else(|| text_field("id"))
                    .map(str::to_string)
                    .unwrap_or_else(|| uuid::Uuid::new_v4().to_string().to_uppercase());
                let name = text_field("name").unwrap_or("shell");
                let arguments = text_field("arguments").or_else(|| text_field("input")).unwrap_or("");
                state.pending_tools.insert(id, PendingTool::new(name, arguments, date));
            }
            Some("function_call_output" | "custom_tool_call_output" | "local_shell_call_output") => {
                if let Some(id) = text_field("call_id") {
                    state.pending_tools.remove(id);
                }
                state.approval_requested_at = None;
            }
            _ => {}
        }
    }

    fn consume_event(
        &mut self,
        payload: &Value,
        payload_type: Option<&str>,
        date: Option<Timestamp>,
        path: &Path,
        state: &mut TranscriptState,
    ) {
        match payload_type {
            Some("user_message") => {
                if !self.uses_event_prompts(path) {
                    self.event_prompts.insert(path.to_path_buf(), true);
                    state.prompts.clear();
                    state.messages.retain(|message| message.role != MessageRole::User);
                }
                if let Some(message) = payload.get("message").and_then(Value::as_str) {
                    if let Some(clean) = ContentText::clean_user_text(message) {
                        state.record_prompt(Harness::Codex, &clean, date);
                    }
                }
            }
            Some("task_started") => state.turn_started_at = date,
            Some("task_complete" | "turn_aborted") => {
                state.turn_ended_at = date;
                state.pending_tools.clear();
                state.approval_requested_at = None;
            }
            Some("exec_approval_request" | "apply_patch_approval_request" | "request_user_input") => {
                state.approval_requested_at = date;
            }
            Some("exec_command_end" | "patch_apply_end" | "exec_command_begin") => {
                state.approval_requested_at = None;
            }
            Some("token_count") => {
                self.record_token_count(payload, date, path, state);
                self.record_rate_limits(payload, date, path);
            }
            _ => {}
        }
    }

    fn record_token_count(&mut self, payload: &Value, date: Option<Timestamp>, path: &Path, state: &mut TranscriptState) {
        let Some(total) = object_field(payload, "info").and_then(|info| object_field(info, "total_token_usage")) else {
            return;
        };
        let cached = int_or_zero(total, "cached_input_tokens");
        let current = TokenUsage::new(
            (int_or_zero(total, "input_tokens") - cached).max(0),
            int_or_zero(total, "output_tokens"),
            cached,
            int_or_zero(total, "cache_write_input_tokens"),
        );
        let previous = self.last_totals.get(path).copied().unwrap_or_default();
        if current.total() >= previous.total() {
            state.add_usage(current - previous, date);
            self.last_totals.insert(path.to_path_buf(), current);
        }
    }

    fn record_rate_limits(&mut self, payload: &Value, date: Option<Timestamp>, path: &Path) {
        let (Some(limits), Some(date)) = (object_field(payload, "rate_limits"), date) else { return };
        let mut windows = Vec::new();
        for (key, label) in [("primary", tr("Short window")), ("secondary", tr("Week"))] {
            let Some(window) = object_field(limits, key) else { continue };
            let Some(used) = window.get("used_percent").and_then(Value::as_f64) else { continue };
            let minutes = json_int(window.get("window_minutes"));
            windows.push(RateWindow {
                label: minutes.map(Self::window_label).unwrap_or(label),
                used_percent: used,
                resets_at: parse_date(window.get("resets_at")),
                window_minutes: minutes,
            });
        }
        if !windows.is_empty() {
            let plan = limits.get("plan_type").and_then(Value::as_str).map(str::to_string);
            self.rate_snapshots.insert(path.to_path_buf(), CodexRateSnapshot { observed_at: date, windows, plan });
        }
    }

    pub fn window_label(minutes: i64) -> String {
        if minutes >= MINUTES_PER_WEEK - 1 {
            return tr("Week");
        }
        if minutes >= MINUTES_PER_DAY {
            return trf!("%d days", minutes / MINUTES_PER_DAY);
        }
        trf!("%d h", minutes / 60)
    }
}
