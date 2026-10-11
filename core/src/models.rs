use std::ops::{Add, Sub};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::localization::tr;

pub type Timestamp = DateTime<Utc>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Harness {
    Claude,
    Codex,
    Gemini,
    Copilot,
    Cursor,
    Pi,
    Omp,
}

impl Harness {
    pub const ALL: [Harness; 7] = [
        Harness::Claude,
        Harness::Codex,
        Harness::Gemini,
        Harness::Copilot,
        Harness::Cursor,
        Harness::Pi,
        Harness::Omp,
    ];

    pub fn raw(self) -> &'static str {
        match self {
            Harness::Claude => "claude",
            Harness::Codex => "codex",
            Harness::Gemini => "gemini",
            Harness::Copilot => "copilot",
            Harness::Cursor => "cursor",
            Harness::Pi => "pi",
            Harness::Omp => "omp",
        }
    }

    pub fn from_raw(raw: &str) -> Option<Harness> {
        Harness::ALL.into_iter().find(|h| h.raw() == raw)
    }

    pub fn display_name(self) -> &'static str {
        match self {
            Harness::Claude => "Claude Code",
            Harness::Codex => "Codex",
            Harness::Gemini => "Gemini",
            Harness::Copilot => "Copilot",
            Harness::Cursor => "Cursor",
            Harness::Pi => "Pi",
            Harness::Omp => "omp",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AgentStatus {
    Working,
    NeedsApproval,
    Finished,
}

impl AgentStatus {
    pub fn label(self) -> String {
        match self {
            AgentStatus::Working => tr("Working"),
            AgentStatus::NeedsApproval => tr("Needs your approval"),
            AgentStatus::Finished => tr("Done"),
        }
    }

    pub fn priority(self) -> u8 {
        match self {
            AgentStatus::NeedsApproval => 0,
            AgentStatus::Working => 1,
            AgentStatus::Finished => 2,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenUsage {
    pub input: i64,
    pub output: i64,
    pub cache_read: i64,
    pub cache_write: i64,
}

impl TokenUsage {
    pub fn new(input: i64, output: i64, cache_read: i64, cache_write: i64) -> Self {
        TokenUsage { input, output, cache_read, cache_write }
    }

    pub fn total(&self) -> i64 {
        self.input + self.output + self.cache_read + self.cache_write
    }
}

impl Add for TokenUsage {
    type Output = TokenUsage;
    fn add(self, rhs: TokenUsage) -> TokenUsage {
        TokenUsage::new(
            self.input + rhs.input,
            self.output + rhs.output,
            self.cache_read + rhs.cache_read,
            self.cache_write + rhs.cache_write,
        )
    }
}

impl Sub for TokenUsage {
    type Output = TokenUsage;
    fn sub(self, rhs: TokenUsage) -> TokenUsage {
        TokenUsage::new(
            self.input - rhs.input,
            self.output - rhs.output,
            self.cache_read - rhs.cache_read,
            self.cache_write - rhs.cache_write,
        )
    }
}

impl std::iter::Sum for TokenUsage {
    fn sum<I: Iterator<Item = TokenUsage>>(iter: I) -> TokenUsage {
        iter.fold(TokenUsage::default(), |a, b| a + b)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MessageRole {
    User,
    Assistant,
    Tool,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptMessage {
    pub role: MessageRole,
    pub text: String,
    pub timestamp: Option<Timestamp>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSession {
    pub id: String,
    pub harness: Harness,
    pub session_id: String,
    pub title: String,
    pub cwd: String,
    pub project_name: String,
    pub status: AgentStatus,
    pub started_at: Option<Timestamp>,
    pub updated_at: Timestamp,
    pub last_prompt: Option<String>,
    pub last_reply: Option<String>,
    pub pending_action: Option<String>,
    pub model: Option<String>,
    pub tokens: TokenUsage,
    pub prompt_count: i64,
    pub pid: Option<u32>,
    pub transcript_path: Option<String>,
    pub is_live: bool,
}

impl AgentSession {
    pub fn new(harness: Harness, session_id: impl Into<String>, title: impl Into<String>, cwd: impl Into<String>, status: AgentStatus, updated_at: Timestamp) -> Self {
        let session_id = session_id.into();
        let cwd = cwd.into();
        AgentSession {
            id: format!("{}:{}", harness.raw(), session_id),
            harness,
            project_name: crate::util::last_path_component(&cwd),
            session_id,
            title: title.into(),
            cwd,
            status,
            started_at: None,
            updated_at,
            last_prompt: None,
            last_reply: None,
            pending_action: None,
            model: None,
            tokens: TokenUsage::default(),
            prompt_count: 0,
            pid: None,
            transcript_path: None,
            is_live: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserPrompt {
    pub harness: Harness,
    pub session_id: String,
    pub cwd: String,
    pub text: String,
    pub timestamp: Option<Timestamp>,
    pub previous_assistant: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DailyTokens {
    pub day: String,
    pub harness: Harness,
    pub tokens: TokenUsage,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RateWindow {
    pub label: String,
    pub used_percent: f64,
    pub resets_at: Option<Timestamp>,
    pub window_minutes: Option<i64>,
}

impl RateWindow {
    pub fn rolled_over(mut self, current: Timestamp) -> Self {
        if self.resets_at.is_some_and(|reset| reset <= current) {
            self.used_percent = 0.0;
            self.resets_at = None;
        }
        self
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct CodexRateSnapshot {
    pub observed_at: Timestamp,
    pub windows: Vec<RateWindow>,
    pub plan: Option<String>,
}
