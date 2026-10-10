use std::collections::HashMap;
use std::path::Path;
use std::sync::{Mutex, MutexGuard};

use crate::claude::ClaudeSource;
use crate::codex::CodexSource;
use crate::copilot::CopilotSource;
use crate::cursor::CursorSource;
use crate::gemini::GeminiSource;
use crate::models::{AgentSession, CodexRateSnapshot, DailyTokens, Harness, TokenUsage, TranscriptMessage, UserPrompt};
use crate::paths::Paths;
use crate::pi::PiSource;
use crate::rule_writer;
use crate::transcript::path_string;

struct Sources {
    claude: ClaudeSource,
    codex: CodexSource,
    pi: PiSource,
    omp: PiSource,
    cursor: CursorSource,
    gemini: GeminiSource,
    copilot: CopilotSource,
}

pub struct AgentMonitor {
    sources: Mutex<Sources>,
}

impl Default for AgentMonitor {
    fn default() -> Self {
        AgentMonitor::new(true)
    }
}

fn own_directory() -> String {
    path_string(&rule_writer::working_directory())
}

impl AgentMonitor {
    pub fn new(keep_messages: bool) -> Self {
        let mut sources = Sources {
            claude: ClaudeSource::default(),
            codex: CodexSource::default(),
            pi: PiSource::new(Harness::Pi, Paths::pi()),
            omp: PiSource::new(Harness::Omp, Paths::omp()),
            cursor: CursorSource::new(),
            gemini: GeminiSource::default(),
            copilot: CopilotSource::default(),
        };
        sources.claude.keep_messages = keep_messages;
        sources.codex.keep_messages = keep_messages;
        sources.pi.keep_messages = keep_messages;
        sources.omp.keep_messages = keep_messages;
        sources.copilot.keep_messages = keep_messages;
        AgentMonitor { sources: Mutex::new(sources) }
    }

    fn lock(&self) -> MutexGuard<'_, Sources> {
        self.sources.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub fn sessions(&self) -> Vec<AgentSession> {
        let mut sources = self.lock();
        let own = own_directory();
        let mut all = sources.claude.sessions();
        all.extend(sources.codex.sessions());
        all.extend(sources.pi.sessions());
        all.extend(sources.omp.sessions());
        all.extend(sources.gemini.sessions());
        all.extend(sources.copilot.sessions());
        let known: Vec<String> = all.iter().map(|session| session.cwd.clone()).collect();
        all.extend(sources.cursor.sessions(&known));
        all.retain(|session| !session.cwd.starts_with(&own));
        all.sort_by(|a, b| {
            a.status.priority().cmp(&b.status.priority()).then_with(|| b.updated_at.cmp(&a.updated_at))
        });
        all
    }

    pub fn messages(&self, session: &AgentSession) -> Vec<TranscriptMessage> {
        let mut sources = self.lock();
        let path = session.transcript_path.as_deref().map(Path::new);
        match (session.harness, path) {
            (Harness::Claude, _) => sources.claude.messages(&session.session_id),
            (Harness::Codex, Some(path)) => sources.codex.parse(path).messages.clone(),
            (Harness::Codex, None) => sources.codex.messages(&session.session_id),
            (Harness::Pi, Some(path)) => sources.pi.parse(path).messages.clone(),
            (Harness::Omp, Some(path)) => sources.omp.parse(path).messages.clone(),
            (Harness::Gemini, Some(path)) => sources.gemini.messages(path),
            (Harness::Copilot, Some(path)) => sources.copilot.messages(path),
            (Harness::Pi | Harness::Omp | Harness::Gemini | Harness::Copilot, None) | (Harness::Cursor, _) => Vec::new(),
        }
    }

    pub fn prompts(&self, window_secs: f64) -> Vec<UserPrompt> {
        let mut sources = self.lock();
        let own = own_directory();
        let mut prompts = sources.claude.all_prompts(window_secs);
        prompts.extend(sources.codex.all_prompts(window_secs));
        prompts.extend(sources.pi.all_prompts(window_secs));
        prompts.extend(sources.omp.all_prompts(window_secs));
        prompts.extend(sources.gemini.all_prompts(window_secs));
        prompts.extend(sources.copilot.all_prompts(window_secs));
        prompts.retain(|prompt| !prompt.cwd.starts_with(&own));
        prompts
    }

    pub fn daily_tokens(&self, window_secs: f64) -> Vec<DailyTokens> {
        let mut sources = self.lock();
        let by_harness: [(Harness, HashMap<String, TokenUsage>); 6] = [
            (Harness::Claude, sources.claude.tokens_by_day(window_secs)),
            (Harness::Codex, sources.codex.tokens_by_day(window_secs)),
            (Harness::Pi, sources.pi.tokens_by_day(window_secs)),
            (Harness::Omp, sources.omp.tokens_by_day(window_secs)),
            (Harness::Gemini, sources.gemini.tokens_by_day(window_secs)),
            (Harness::Copilot, sources.copilot.tokens_by_day(window_secs)),
        ];
        let mut result: Vec<DailyTokens> = by_harness
            .into_iter()
            .flat_map(|(harness, days)| {
                days.into_iter()
                    .filter(|(_, usage)| usage.total() > 0)
                    .map(move |(day, tokens)| DailyTokens { day, harness, tokens })
            })
            .collect();
        result.sort_by(|a, b| a.day.cmp(&b.day));
        result
    }

    pub fn codex_rate_limits(&self) -> Option<CodexRateSnapshot> {
        self.lock().codex.latest_rate_limits()
    }

    pub fn installed_harnesses(&self) -> Vec<Harness> {
        [
            (Harness::Claude, Paths::claude()),
            (Harness::Codex, Paths::codex()),
            (Harness::Cursor, Paths::cursor()),
            (Harness::Pi, Paths::pi()),
            (Harness::Omp, Paths::omp()),
            (Harness::Gemini, Paths::gemini()),
            (Harness::Copilot, Paths::copilot()),
        ]
        .into_iter()
        .filter(|(_, path)| path.exists())
        .map(|(harness, _)| harness)
        .collect()
    }
}
