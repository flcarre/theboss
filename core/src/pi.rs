use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::jsonl::{int_or_zero, object_array, object_field};
use crate::localization::tr;
use crate::models::{AgentSession, AgentStatus, Harness, MessageRole, Timestamp, TokenUsage, TranscriptMessage, UserPrompt};
use crate::transcript::{
    cutoff, jsonl_files_under, merge_days, path_string, ContentText, PendingTool, TranscriptState, DEFAULT_RECENT_WINDOW,
};
use crate::util::{modified, now, parse_date, seconds_since};

const LIVE_WINDOW: f64 = 600.0;

pub struct PiSource {
    states: HashMap<PathBuf, TranscriptState>,
    pub harness: Harness,
    pub root: PathBuf,
    recent_window: f64,
    pub keep_messages: bool,
}

impl PiSource {
    pub fn new(harness: Harness, root: PathBuf) -> Self {
        PiSource::with_window(harness, root, DEFAULT_RECENT_WINDOW)
    }

    pub fn with_window(harness: Harness, root: PathBuf, recent_window: f64) -> Self {
        PiSource { states: HashMap::new(), harness, root, recent_window, keep_messages: true }
    }

    pub fn sessions_dir(&self) -> PathBuf {
        self.root.join("agent").join("sessions")
    }

    pub fn files(&self, window_secs: f64) -> Vec<PathBuf> {
        jsonl_files_under(&self.sessions_dir(), Some(cutoff(window_secs)))
    }

    pub fn sessions(&mut self) -> Vec<AgentSession> {
        let harness = self.harness;
        let mut result = Vec::new();
        for path in self.files(self.recent_window) {
            let state = self.parse(&path);
            if state.prompts.is_empty() {
                continue;
            }
            let modified = modified(&path).unwrap_or_else(now);
            let idle = seconds_since(modified);
            let last_role = state.messages.last().map(|message| message.role);
            let status = if idle < 15.0 || (last_role != Some(MessageRole::Assistant) && idle < 120.0) {
                AgentStatus::Working
            } else if !state.pending_tools.is_empty() && idle < 3600.0 {
                AgentStatus::NeedsApproval
            } else {
                AgentStatus::Finished
            };
            let id = state.session_id.clone().unwrap_or_else(|| {
                path.file_stem().map(|stem| stem.to_string_lossy().into_owned()).unwrap_or_default()
            });
            let mut session =
                AgentSession::new(harness, id, state.display_title(), state.cwd.clone().unwrap_or_default(), status, modified);
            session.started_at = state.started_at;
            session.last_prompt = state.last_prompt();
            session.last_reply = state.last_assistant_text.clone();
            session.pending_action = if status == AgentStatus::NeedsApproval { state.pending_description() } else { None };
            session.model = state.model.clone();
            session.tokens = state.tokens;
            session.prompt_count = state.prompts.len() as i64;
            session.transcript_path = Some(path_string(&path));
            session.is_live = idle < LIVE_WINDOW;
            result.push(session);
        }
        result
    }

    pub fn messages(&self, session_id: &str) -> Vec<TranscriptMessage> {
        self.states
            .values()
            .find(|state| state.session_id.as_deref() == Some(session_id))
            .map(|state| state.messages.clone())
            .unwrap_or_default()
    }

    pub fn all_prompts(&mut self, window_secs: f64) -> Vec<UserPrompt> {
        let files = self.files(window_secs);
        files.iter().flat_map(|file| self.parse(file).prompts.clone()).collect()
    }

    pub fn tokens_by_day(&mut self, window_secs: f64) -> HashMap<String, TokenUsage> {
        let mut result = HashMap::new();
        for file in self.files(window_secs) {
            merge_days(&mut result, &self.parse(&file).tokens_by_day);
        }
        result
    }

    pub fn parse(&mut self, path: &Path) -> &TranscriptState {
        let keep_messages = self.keep_messages;
        let harness = self.harness;
        let state = self.states.entry(path.to_path_buf()).or_insert_with(|| TranscriptState::new(keep_messages));
        let (objects, reset) = state.tail.read_new_objects(path);
        if reset {
            state.reset();
        }
        for object in &objects {
            Self::consume(harness, object, state);
        }
        state
    }

    pub fn tokens(usage: &Value) -> TokenUsage {
        TokenUsage::new(
            int_or_zero(usage, "input"),
            int_or_zero(usage, "output"),
            int_or_zero(usage, "cacheRead"),
            int_or_zero(usage, "cacheWrite"),
        )
    }

    fn consume(harness: Harness, object: &Value, state: &mut TranscriptState) {
        let date = parse_date(object.get("timestamp"));
        state.touch(date);
        let text_field = |key: &str| object.get(key).and_then(Value::as_str).map(str::to_string);
        match object.get("type").and_then(Value::as_str) {
            Some("session") => {
                state.session_id = text_field("id");
                state.cwd = text_field("cwd");
            }
            Some("session_info") => {
                if let Some(name) = text_field("name") {
                    state.title = Some(name);
                }
            }
            Some("model_change") => {
                if let Some(model) = text_field("modelId") {
                    state.model = Some(model);
                }
            }
            Some("usage" | "compaction" | "branch_summary") => {
                if let Some(usage) = object_field(object, "usage") {
                    state.add_usage(Self::tokens(usage), date);
                }
            }
            Some("message") => {
                if let Some(message) = object_field(object, "message") {
                    Self::consume_message(harness, message, date, state);
                }
            }
            _ => {}
        }
    }

    fn consume_message(harness: Harness, message: &Value, date: Option<Timestamp>, state: &mut TranscriptState) {
        match message.get("role").and_then(Value::as_str) {
            Some("user") => {
                if let Some(text) = ContentText::clean_user_text(&ContentText::extract_default(message.get("content"))) {
                    state.record_prompt(harness, &text, date);
                }
            }
            Some("assistant") => {
                if let Some(model) = message.get("model").and_then(Value::as_str) {
                    state.model = Some(model.to_string());
                }
                if let Some(usage) = object_field(message, "usage") {
                    state.add_usage(Self::tokens(usage), date);
                }
                if let Some(blocks) = object_array(message.get("content")) {
                    for block in blocks.iter().filter(|block| block.get("type").and_then(Value::as_str) == Some("toolCall")) {
                        let id = block
                            .get("id")
                            .and_then(Value::as_str)
                            .map(str::to_string)
                            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string().to_uppercase());
                        let name = block.get("name").and_then(Value::as_str).map(str::to_string).unwrap_or_else(|| tr("tool"));
                        let arguments = object_field(block, "arguments");
                        let field = |key: &str| arguments.and_then(|args| args.get(key)).and_then(Value::as_str);
                        let detail = field("command").or_else(|| field("path")).unwrap_or("");
                        state.pending_tools.insert(id, PendingTool::new(name, detail, date));
                    }
                }
                state.record_reply(&ContentText::extract_default(message.get("content")), date);
            }
            Some("toolResult") => {
                if let Some(id) = message.get("toolCallId").and_then(Value::as_str) {
                    state.pending_tools.remove(id);
                }
            }
            _ => {}
        }
    }
}
