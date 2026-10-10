use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::jsonl::{captures, contains_bytes, int_or_zero, json_int, object_array, object_field, JsonlTail};
use crate::localization::tr;
use crate::models::{AgentSession, AgentStatus, Harness, Timestamp, TokenUsage, TranscriptMessage, UserPrompt};
use crate::paths::Paths;
use crate::transcript::{
    cutoff, has_extension, is_modified_since, merge_days, path_string, ContentText, PendingTool, TranscriptState,
    DEFAULT_RECENT_WINDOW,
};
use crate::util::{is_process_alive, modified, now, parse_date, parse_date_str, seconds_since};

pub const INTERESTING_MARKERS: &[&str] = &["\"user\"", "\"assistant\"", "\"custom-title\"", "\"summary\""];

#[derive(Debug, Clone, PartialEq)]
pub struct ClaudeLiveSession {
    pub pid: u32,
    pub session_id: String,
    pub cwd: String,
    pub name: Option<String>,
    pub status: Option<String>,
    pub started_at: Option<Timestamp>,
    pub updated_at: Option<Timestamp>,
}

pub struct ClaudeSource {
    states: HashMap<PathBuf, TranscriptState>,
    recent_window: f64,
    pub keep_messages: bool,
}

impl Default for ClaudeSource {
    fn default() -> Self {
        ClaudeSource::new(DEFAULT_RECENT_WINDOW)
    }
}

impl ClaudeSource {
    pub fn new(recent_window: f64) -> Self {
        ClaudeSource { states: HashMap::new(), recent_window, keep_messages: true }
    }

    pub fn projects_dir(&self) -> PathBuf {
        Paths::claude().join("projects")
    }

    pub fn live_sessions(&self) -> Vec<ClaudeLiveSession> {
        let Ok(entries) = std::fs::read_dir(Paths::claude().join("sessions")) else { return Vec::new() };
        entries
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| has_extension(path, "json"))
            .filter_map(|path| Self::live_session(&path))
            .collect()
    }

    fn live_session(path: &Path) -> Option<ClaudeLiveSession> {
        let data = std::fs::read(path).ok()?;
        let json: Value = serde_json::from_slice(&data).ok()?;
        let pid = u32::try_from(json_int(json.get("pid"))?).ok()?;
        let session_id = json.get("sessionId")?.as_str()?.to_string();
        if !is_process_alive(pid) {
            return None;
        }
        Some(ClaudeLiveSession {
            pid,
            session_id,
            cwd: json.get("cwd").and_then(Value::as_str).unwrap_or_default().to_string(),
            name: json.get("name").and_then(Value::as_str).map(str::to_string),
            status: json.get("status").and_then(Value::as_str).map(str::to_string),
            started_at: parse_date(json.get("startedAt")),
            updated_at: parse_date(json.get("updatedAt")),
        })
    }

    pub fn transcript_files(&self, window_secs: Option<f64>) -> Vec<PathBuf> {
        let Ok(projects) = std::fs::read_dir(self.projects_dir()) else { return Vec::new() };
        let cutoff = window_secs.map(cutoff);
        let mut result = Vec::new();
        for project in projects.filter_map(Result::ok) {
            let Ok(files) = std::fs::read_dir(project.path()) else { continue };
            result.extend(
                files
                    .filter_map(Result::ok)
                    .map(|entry| entry.path())
                    .filter(|path| has_extension(path, "jsonl") && is_modified_since(path, cutoff)),
            );
        }
        result
    }

    pub fn sessions(&mut self) -> Vec<AgentSession> {
        let live = self.live_sessions();
        let mut live_by_id: HashMap<String, ClaudeLiveSession> = HashMap::new();
        for session in &live {
            live_by_id.entry(session.session_id.clone()).or_insert_with(|| session.clone());
        }
        let mut paths_by_id: HashMap<String, PathBuf> = HashMap::new();
        for file in self.transcript_files(Some(self.recent_window)) {
            if let Some(stem) = file.file_stem() {
                paths_by_id.insert(stem.to_string_lossy().into_owned(), file);
            }
        }
        for session in &live {
            if paths_by_id.contains_key(&session.session_id) {
                continue;
            }
            if let Some(file) = self.locate_transcript(&session.session_id) {
                paths_by_id.insert(session.session_id.clone(), file);
            }
        }

        let mut result = Vec::new();
        for (session_id, path) in &paths_by_id {
            let live_info = live_by_id.get(session_id);
            let state = self.parse(path);
            if state.prompts.is_empty() && live_info.is_none() {
                continue;
            }
            let modified = modified(path).or(state.last_activity).unwrap_or_else(now);
            let status = Self::status(live_info, state, modified);
            let title = live_info.and_then(|live| live.name.clone()).unwrap_or_else(|| state.display_title());
            let cwd = live_info.map(|live| live.cwd.clone()).or_else(|| state.cwd.clone()).unwrap_or_default();
            let mut session = AgentSession::new(Harness::Claude, session_id.clone(), title, cwd, status, modified);
            session.started_at = state.started_at.or(live_info.and_then(|live| live.started_at));
            session.updated_at = match live_info.and_then(|live| live.updated_at) {
                Some(live_updated) if live_updated > modified => live_updated,
                _ => modified,
            };
            session.last_prompt = state.last_prompt();
            session.last_reply = state.last_assistant_text.clone();
            session.pending_action = if status == AgentStatus::NeedsApproval { state.pending_description() } else { None };
            session.model = state.model.clone();
            session.tokens = state.tokens;
            session.prompt_count = state.prompts.len() as i64;
            session.pid = live_info.map(|live| live.pid);
            session.transcript_path = Some(path_string(path));
            session.is_live = live_info.is_some();
            result.push(session);
        }
        for live_session in live.iter().filter(|live| !paths_by_id.contains_key(&live.session_id)) {
            let mut session = AgentSession::new(
                Harness::Claude,
                live_session.session_id.clone(),
                live_session.name.clone().unwrap_or_else(|| tr("New session")),
                live_session.cwd.clone(),
                Self::map(live_session.status.as_deref()).unwrap_or(AgentStatus::Finished),
                live_session.updated_at.unwrap_or_else(now),
            );
            session.started_at = live_session.started_at;
            session.pid = Some(live_session.pid);
            session.is_live = true;
            result.push(session);
        }
        result
    }

    pub fn map(live_status: Option<&str>) -> Option<AgentStatus> {
        match live_status? {
            "busy" | "running" | "working" => Some(AgentStatus::Working),
            "waiting" | "needs_input" | "awaiting_approval" | "waiting_for_permission" => Some(AgentStatus::NeedsApproval),
            "idle" => Some(AgentStatus::Finished),
            _ => None,
        }
    }

    pub fn status(live: Option<&ClaudeLiveSession>, state: &TranscriptState, modified: Timestamp) -> AgentStatus {
        if let Some(mapped) = Self::map(live.and_then(|live| live.status.as_deref())) {
            return mapped;
        }
        let idle = seconds_since(modified);
        if !state.pending_tools.is_empty() && idle > 8.0 && live.is_some() {
            return AgentStatus::NeedsApproval;
        }
        if idle < 15.0 {
            return AgentStatus::Working;
        }
        AgentStatus::Finished
    }

    pub fn locate_transcript(&self, session_id: &str) -> Option<PathBuf> {
        let projects = std::fs::read_dir(self.projects_dir()).ok()?;
        let file_name = format!("{session_id}.jsonl");
        projects
            .filter_map(Result::ok)
            .map(|project| project.path().join(&file_name))
            .find(|candidate| candidate.exists())
    }

    pub fn messages(&mut self, session_id: &str) -> Vec<TranscriptMessage> {
        match self.locate_transcript(session_id) {
            Some(path) => self.parse(&path).messages.clone(),
            None => Vec::new(),
        }
    }

    pub fn parse(&mut self, path: &Path) -> &TranscriptState {
        let keep_messages = self.keep_messages;
        let state = self.states.entry(path.to_path_buf()).or_insert_with(|| TranscriptState::new(keep_messages));
        let (lines, reset) = state.tail.read_new_lines(path);
        if reset {
            state.reset();
        }
        for line in &lines {
            Self::consume_line(line, state);
        }
        state
    }

    pub fn all_prompts(&mut self, window_secs: f64) -> Vec<UserPrompt> {
        let files = self.transcript_files(Some(window_secs));
        files.iter().flat_map(|file| self.parse(file).prompts.clone()).collect()
    }

    pub fn tokens_by_day(&mut self, window_secs: f64) -> HashMap<String, TokenUsage> {
        let mut result = HashMap::new();
        for file in self.transcript_files(Some(window_secs)) {
            merge_days(&mut result, &self.parse(&file).tokens_by_day);
        }
        result
    }

    pub fn consume_line(line: &[u8], state: &mut TranscriptState) {
        if !INTERESTING_MARKERS.iter().any(|marker| contains_bytes(line, marker)) {
            return;
        }
        if contains_bytes(line, "\"tool_result\"") && !contains_bytes(line, "\"assistant\"") {
            let compact = !contains_bytes(line, "\": \"");
            if compact {
                for id in captures(line, "\"tool_use_id\":\"", crate::jsonl::DEFAULT_CAPTURE_LIMIT) {
                    state.pending_tools.remove(&id);
                }
                if let Some(stamp) = captures(line, "\"timestamp\":\"", 1).first() {
                    state.touch(parse_date_str(stamp));
                }
                if state.session_id.is_none() {
                    if let Some(id) = captures(line, "\"sessionId\":\"", 1).into_iter().next() {
                        state.session_id = Some(id);
                    }
                }
                if state.cwd.is_none() {
                    if let Some(cwd) = captures(line, "\"cwd\":\"", 1).into_iter().next() {
                        state.cwd = Some(cwd);
                    }
                }
                return;
            }
        }
        let Some(object) = JsonlTail::object(line) else { return };
        Self::consume(&object, state);
    }

    pub fn consume(object: &Value, state: &mut TranscriptState) {
        let kind = object.get("type").and_then(Value::as_str);
        let date = parse_date(object.get("timestamp"));
        if state.session_id.is_none() {
            if let Some(id) = object.get("sessionId").and_then(Value::as_str) {
                state.session_id = Some(id.to_string());
            }
        }
        if state.cwd.is_none() {
            if let Some(cwd) = object.get("cwd").and_then(Value::as_str) {
                state.cwd = Some(cwd.to_string());
            }
        }

        match kind {
            Some("custom-title") => {
                if let Some(title) = object.get("customTitle").and_then(Value::as_str) {
                    state.title = Some(title.to_string());
                }
            }
            Some("summary") => {
                if state.title.is_none() {
                    if let Some(summary) = object.get("summary").and_then(Value::as_str) {
                        state.title = Some(summary.to_string());
                    }
                }
            }
            Some("user") => Self::consume_user(object, date, state),
            Some("assistant") => Self::consume_assistant(object, date, state),
            _ => {}
        }
    }

    fn is_sidechain(object: &Value) -> bool {
        object.get("isSidechain").and_then(Value::as_bool) == Some(true)
    }

    fn consume_user(object: &Value, date: Option<Timestamp>, state: &mut TranscriptState) {
        state.touch(date);
        if Self::is_sidechain(object) {
            return;
        }
        let Some(message) = object_field(object, "message") else { return };
        if let Some(blocks) = object_array(message.get("content")) {
            for block in blocks.iter().filter(|block| block.get("type").and_then(Value::as_str) == Some("tool_result")) {
                if let Some(id) = block.get("tool_use_id").and_then(Value::as_str) {
                    state.pending_tools.remove(id);
                }
            }
        }
        let flagged = |key: &str| object.get(key).and_then(Value::as_bool) == Some(true);
        if flagged("isMeta") || flagged("isCompactSummary") {
            return;
        }
        let raw = ContentText::extract(message.get("content"), &["text"]);
        if let Some(text) = ContentText::clean_user_text(&raw) {
            state.record_prompt(Harness::Claude, &text, date);
        }
    }

    fn consume_assistant(object: &Value, date: Option<Timestamp>, state: &mut TranscriptState) {
        state.touch(date);
        if Self::is_sidechain(object) {
            return;
        }
        let Some(message) = object_field(object, "message") else { return };
        if let Some(model) = message.get("model").and_then(Value::as_str) {
            if !model.starts_with('<') {
                state.model = Some(model.to_string());
            }
        }
        if let (Some(id), Some(usage)) = (message.get("id").and_then(Value::as_str), object_field(message, "usage")) {
            let current = TokenUsage::new(
                int_or_zero(usage, "input_tokens"),
                int_or_zero(usage, "output_tokens"),
                int_or_zero(usage, "cache_read_input_tokens"),
                int_or_zero(usage, "cache_creation_input_tokens"),
            );
            let previous = state.usage_by_id.get(id).copied().unwrap_or_default();
            state.add_usage(current - previous, date);
            state.usage_by_id.insert(id.to_string(), current);
        }
        if let Some(blocks) = object_array(message.get("content")) {
            for block in blocks.iter().filter(|block| block.get("type").and_then(Value::as_str) == Some("tool_use")) {
                let Some(id) = block.get("id").and_then(Value::as_str) else { continue };
                let name = block.get("name").and_then(Value::as_str).map(str::to_string).unwrap_or_else(|| tr("tool"));
                let input = object_field(block, "input");
                let field = |key: &str| input.and_then(|input| input.get(key)).and_then(Value::as_str);
                let detail = field("command").or_else(|| field("file_path")).or_else(|| field("description")).unwrap_or("");
                state.pending_tools.insert(id.to_string(), PendingTool::new(name, detail, date));
            }
        }
        let text = ContentText::extract(message.get("content"), &["text"]);
        if !text.is_empty() {
            state.record_reply(&text, date);
        }
    }
}
