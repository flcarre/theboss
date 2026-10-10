use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, MutexGuard};

use boss_core::analytics::AnalyticsReport;
use boss_core::diff::DiffLine;
use boss_core::monitor::AgentMonitor;
use boss_core::rules::RuleItem;
use boss_core::store::Store;
use boss_core::suggestions::{Suggestion, SuggestionStatus};
use boss_core::usage::{UsageReport, UsageService};
use boss_core::{AgentSession, AgentStatus, AppLanguage, Harness};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub notifications: bool,
    pub sounds: bool,
    pub zoom: f64,
    pub finished_hours: f64,
    pub auto_refine: bool,
    pub language: AppLanguage,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { notifications: true, sounds: true, zoom: 1.5, finished_hours: 6.0, auto_refine: false, language: AppLanguage::English }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SuggestionView {
    #[serde(flatten)]
    pub suggestion: Suggestion,
    pub display_path: String,
    pub diff: Vec<DiffLine>,
}

impl SuggestionView {
    pub fn of(suggestion: Suggestion) -> Self {
        let diff = if suggestion.status == SuggestionStatus::Applied { Vec::new() } else { suggestion.diff() };
        SuggestionView { display_path: suggestion.display_path(), diff, suggestion }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub platform: &'static str,
    pub sessions: Vec<AgentSession>,
    pub usage: Option<UsageReport>,
    pub rules: Vec<RuleItem>,
    pub suggestions: Vec<SuggestionView>,
    pub analytics: Option<AnalyticsReport>,
    pub insights_ready: bool,
    pub settings: Settings,
    pub whip_count: i64,
    pub installed_harnesses: Vec<Harness>,
    pub refining: Vec<String>,
    pub repairing_claude: bool,
}

#[derive(Default)]
pub struct Data {
    pub sessions: Vec<AgentSession>,
    pub usage: Option<UsageReport>,
    pub rules: Vec<RuleItem>,
    pub suggestions: Vec<SuggestionView>,
    pub analytics: Option<AnalyticsReport>,
    pub insights_ready: bool,
    pub insights_running: bool,
    pub settings: Settings,
    pub whip_count: i64,
    pub installed: Vec<Harness>,
    pub refining: HashSet<String>,
    pub repairing_claude: bool,
    pub previous_status: HashMap<String, AgentStatus>,
}

impl Data {
    pub fn open_suggestions(&self) -> impl Iterator<Item = &Suggestion> {
        self.suggestions.iter().map(|view| &view.suggestion).filter(|s| s.status == SuggestionStatus::New)
    }

    pub fn count(&self, status: AgentStatus) -> usize {
        self.sessions.iter().filter(|s| s.status == status).count()
    }

    pub fn suggestion(&self, id: &str) -> Option<Suggestion> {
        self.suggestions.iter().find(|view| view.suggestion.id == id).map(|view| view.suggestion.clone())
    }

    pub fn replace_suggestion(&mut self, suggestion: Suggestion) {
        if let Some(view) = self.suggestions.iter_mut().find(|view| view.suggestion.id == suggestion.id) {
            *view = SuggestionView::of(suggestion);
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        let mut refining: Vec<String> = self.refining.iter().cloned().collect();
        refining.sort();
        Snapshot {
            platform: platform(),
            sessions: self.sessions.clone(),
            usage: self.usage.clone(),
            rules: self.rules.clone(),
            suggestions: self.suggestions.clone(),
            analytics: self.analytics.clone(),
            insights_ready: self.insights_ready,
            settings: self.settings.clone(),
            whip_count: self.whip_count,
            installed_harnesses: self.installed.clone(),
            refining,
            repairing_claude: self.repairing_claude,
        }
    }
}

pub struct Boss {
    pub monitor: Arc<AgentMonitor>,
    pub history: Arc<AgentMonitor>,
    pub store: Arc<Store>,
    pub usage: Arc<UsageService>,
    data: Mutex<Data>,
}

impl Boss {
    pub fn new() -> Self {
        let monitor = Arc::new(AgentMonitor::new(true));
        let history = Arc::new(AgentMonitor::new(false));
        let store = Arc::new(Store::open_default());
        let usage = Arc::new(UsageService::new(history.clone(), monitor.clone()));
        let settings: Settings = store.setting("settings").and_then(|raw| serde_json::from_str(&raw).ok()).unwrap_or_default();
        boss_core::localization::set_language(settings.language);
        let whip_count = store.setting("whips").and_then(|raw| raw.parse().ok()).unwrap_or(0);
        let installed = monitor.installed_harnesses();
        let data = Data { settings, whip_count, installed, ..Data::default() };
        Boss { monitor, history, store, usage, data: Mutex::new(data) }
    }

    pub fn data(&self) -> MutexGuard<'_, Data> {
        self.data.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

pub fn platform() -> &'static str {
    match std::env::consts::OS {
        "macos" => "macos",
        "windows" => "windows",
        _ => "linux",
    }
}
