use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use chrono::{Local, Months};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::cursor_auth;
use crate::localization::tr;
use crate::models::{DailyTokens, Harness, RateWindow, Timestamp, TokenUsage};
use crate::monitor::AgentMonitor;
use crate::paths::Paths;
use crate::trf;
use crate::util::{day_key, get_f64, get_str, now, parse_date, run_with_deadline, ProcessOutcome};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "kind", content = "message", rename_all = "camelCase")]
pub enum UsageState {
    Ok,
    NotInstalled,
    SignedOut,
    KeychainBlocked,
    TokenExpired,
    NoData,
    Failed(String),
}

impl UsageState {
    pub fn problem(&self) -> Option<String> {
        match self {
            UsageState::Ok => None,
            UsageState::NotInstalled => Some(tr("Not installed on this Mac.")),
            UsageState::SignedOut => Some(tr("Claude Code is signed out.")),
            UsageState::KeychainBlocked => Some(tr("macOS is blocking the keychain read.")),
            UsageState::TokenExpired => Some(tr("The sign-in token has expired.")),
            UsageState::NoData => Some(tr("No usage data yet.")),
            UsageState::Failed(message) => Some(message.clone()),
        }
    }

    pub fn fix_steps(&self) -> Vec<String> {
        let keys: &[&str] = match self {
            UsageState::SignedOut => &[
                "Open a terminal and run `claude auth status --text`.",
                "If it says “not logged in”, run `claude auth login`.",
                "Come back here: the gauge fills on the next refresh.",
            ],
            UsageState::KeychainBlocked => &[
                "Open Keychain Access and search for “Claude Code-credentials”.",
                "Access Control tab: add The Boss to “Always allow access by these applications”.",
                "If several items start with that name, do it for each one.",
                "This does not change your Claude account and does not sign you in.",
            ],
            UsageState::TokenExpired => &[
                "Click “Fix automatically”: Claude Code refreshes its token.",
                "If that fails, run `claude auth login` in a terminal.",
                "Come back here: the gauge updates on its own.",
            ],
            UsageState::NoData => &["Start a session: limits arrive with the agent's first reply."],
            _ => &[],
        };
        keys.iter().map(|key| tr(key)).collect()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderUsage {
    pub harness: Harness,
    pub state: UsageState,
    pub plan: Option<String>,
    pub windows: Vec<RateWindow>,
    pub observed_at: Option<Timestamp>,
}

impl ProviderUsage {
    pub fn new(harness: Harness, state: UsageState) -> Self {
        ProviderUsage { harness, state, plan: None, windows: Vec::new(), observed_at: None }
    }

    pub fn with_plan(mut self, plan: Option<String>) -> Self {
        self.plan = plan;
        self
    }

    pub fn with_windows(mut self, windows: Vec<RateWindow>, observed_at: Option<Timestamp>) -> Self {
        self.windows = windows;
        self.observed_at = observed_at;
        self
    }

    pub fn rolled_over(mut self, current: Timestamp) -> Self {
        self.windows = self.windows.into_iter().map(|window| window.rolled_over(current)).collect();
        self
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageReport {
    pub providers: Vec<ProviderUsage>,
    pub daily: Vec<DailyTokens>,
}

impl UsageReport {
    pub fn tokens_on(&self, day: &str) -> TokenUsage {
        self.daily.iter().filter(|entry| entry.day == day).map(|entry| entry.tokens).sum()
    }

    pub fn tokens_last_days(&self, days: i64) -> TokenUsage {
        let cutoff = day_key(now() - chrono::Duration::seconds((days - 1) * 86400));
        self.daily.iter().filter(|entry| entry.day >= cutoff).map(|entry| entry.tokens).sum()
    }

    pub fn today(&self) -> TokenUsage {
        self.tokens_on(&day_key(now()))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClaudeCredentials {
    pub access_token: String,
    pub expires_at: Option<Timestamp>,
    pub subscription: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeychainResult {
    Found(Vec<u8>),
    Missing,
    Blocked,
}

pub type CredentialReader = Arc<dyn Fn() -> KeychainResult + Send + Sync>;

pub const KEYCHAIN_SERVICE: &str = "Claude Code-credentials";
pub const CLAUDE_USAGE_URL: &str = "https://api.anthropic.com/api/oauth/usage";
pub const CURSOR_SUMMARY_URL: &str = "https://cursor.com/api/usage-summary";
pub const CURSOR_LEGACY_URL: &str = "https://cursor.com/api/usage";
pub const HTTP_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UsageEndpoints {
    pub claude_usage: String,
    pub cursor_summary: String,
    pub cursor_legacy: String,
}

impl Default for UsageEndpoints {
    fn default() -> Self {
        UsageEndpoints {
            claude_usage: CLAUDE_USAGE_URL.to_string(),
            cursor_summary: CURSOR_SUMMARY_URL.to_string(),
            cursor_legacy: CURSOR_LEGACY_URL.to_string(),
        }
    }
}

pub fn throttled_message() -> String {
    tr("Anthropic is throttling usage reads. Retrying soon.")
}

pub fn http_agent() -> ureq::Agent {
    ureq::Agent::config_builder().timeout_global(Some(HTTP_TIMEOUT)).http_status_as_error(false).build().into()
}

pub struct HttpResponse {
    pub status: u16,
    pub retry_after: Option<u64>,
    pub body: Vec<u8>,
}

pub fn http_get(agent: &ureq::Agent, url: &str, headers: &[(&str, &str)]) -> Result<HttpResponse, String> {
    let mut request = agent.get(url);
    for (name, value) in headers {
        request = request.header(*name, *value);
    }
    let mut response = request.call().map_err(|error| error.to_string())?;
    let status = response.status().as_u16();
    let retry_after = response
        .headers()
        .get("retry-after")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.trim().parse::<u64>().ok());
    let body = response.body_mut().read_to_vec().map_err(|error| error.to_string())?;
    Ok(HttpResponse { status, retry_after, body })
}

#[derive(Default)]
struct ClaudeCache {
    credentials: Option<ClaudeCredentials>,
    last: Option<ProviderUsage>,
    last_fetch: Option<Timestamp>,
    last_good: Option<ProviderUsage>,
    backoff_until: Option<Timestamp>,
}

pub struct ClaudeUsageClient {
    endpoint: String,
    read_credentials: CredentialReader,
    agent: ureq::Agent,
    cache: Mutex<ClaudeCache>,
}

impl ClaudeUsageClient {
    pub fn new(endpoint: impl Into<String>, read_credentials: CredentialReader) -> Self {
        ClaudeUsageClient {
            endpoint: endpoint.into(),
            read_credentials,
            agent: http_agent(),
            cache: Mutex::new(ClaudeCache::default()),
        }
    }

    fn cache(&self) -> MutexGuard<'_, ClaudeCache> {
        self.cache.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub fn forget_credentials(&self) {
        let mut cache = self.cache();
        cache.credentials = None;
        cache.last_fetch = None;
    }

    pub fn usage(&self, force: bool) -> ProviderUsage {
        if !Paths::claude().exists() {
            return ProviderUsage::new(Harness::Claude, UsageState::NotInstalled);
        }
        {
            let cache = self.cache();
            let current = now();
            if let (Some(until), Some(last)) = (cache.backoff_until, &cache.last) {
                if current < until {
                    return last.clone().rolled_over(current);
                }
            }
            if let (false, Some(last), Some(fetched)) = (force, &cache.last, cache.last_fetch) {
                if (current - fetched).num_milliseconds() < 120_000 {
                    return last.clone().rolled_over(current);
                }
            }
        }
        let fetched = self.fetch();
        let mut cache = self.cache();
        let current = now();
        cache.last_fetch = Some(current);
        let result = match fetched {
            Ok(result) => {
                cache.backoff_until = None;
                if result.state == UsageState::Ok {
                    cache.last_good = Some(result.clone());
                }
                result
            }
            Err(throttle) => {
                cache.backoff_until = Some(current + throttle.backoff());
                cache.last_good.clone().filter(|good| good.state == UsageState::Ok).unwrap_or_else(|| {
                    ProviderUsage::new(Harness::Claude, UsageState::Failed(throttled_message())).with_plan(throttle.plan)
                })
            }
        };
        cache.last = Some(result.clone());
        result.rolled_over(current)
    }

    fn credentials(&self) -> Result<ClaudeCredentials, UsageState> {
        if let Some(credentials) = self.cache().credentials.clone() {
            return Ok(credentials);
        }
        let credentials = match (self.read_credentials)() {
            KeychainResult::Missing => return Err(UsageState::SignedOut),
            KeychainResult::Blocked => return Err(UsageState::KeychainBlocked),
            KeychainResult::Found(data) => decode_credentials(&data).ok_or(UsageState::SignedOut)?,
        };
        self.cache().credentials = Some(credentials.clone());
        Ok(credentials)
    }

    fn fetch(&self) -> Result<ProviderUsage, Throttle> {
        let credentials = match self.credentials() {
            Ok(credentials) => credentials,
            Err(state) => return Ok(ProviderUsage::new(Harness::Claude, state)),
        };
        let plan = credentials.subscription.clone();
        let failed = |message: String| ProviderUsage::new(Harness::Claude, UsageState::Failed(message)).with_plan(plan.clone());
        let authorization = format!("Bearer {}", credentials.access_token);
        let headers = [
            ("Authorization", authorization.as_str()),
            ("anthropic-beta", "oauth-2025-04-20"),
            ("Accept", "application/json"),
        ];
        let response = match http_get(&self.agent, &self.endpoint, &headers) {
            Ok(response) => response,
            Err(error) => return Ok(failed(trf!("Network unavailable: %@", error))),
        };
        Ok(match response.status {
            401 | 403 => {
                self.cache().credentials = None;
                ProviderUsage::new(Harness::Claude, UsageState::TokenExpired).with_plan(plan)
            }
            429 => return Err(Throttle { retry_after: response.retry_after, plan }),
            200 => ProviderUsage::new(Harness::Claude, UsageState::Ok)
                .with_plan(plan)
                .with_windows(parse_claude_windows(&response.body), Some(now())),
            code => failed(trf!("HTTP %d response from Anthropic.", i64::from(code))),
        })
    }
}

const DEFAULT_THROTTLE_BACKOFF: u64 = 300;
const MAX_THROTTLE_BACKOFF: u64 = 3600;

struct Throttle {
    retry_after: Option<u64>,
    plan: Option<String>,
}

impl Throttle {
    fn backoff(&self) -> chrono::Duration {
        let seconds = self.retry_after.unwrap_or(DEFAULT_THROTTLE_BACKOFF).clamp(60, MAX_THROTTLE_BACKOFF);
        chrono::Duration::seconds(seconds as i64)
    }
}

pub struct UsageOptions {
    pub endpoints: UsageEndpoints,
    pub read_credentials: CredentialReader,
}

impl Default for UsageOptions {
    fn default() -> Self {
        UsageOptions { endpoints: UsageEndpoints::default(), read_credentials: Arc::new(read_claude_credentials) }
    }
}

pub struct UsageService {
    monitor: Arc<AgentMonitor>,
    live_monitor: Arc<AgentMonitor>,
    claude: ClaudeUsageClient,
    endpoints: UsageEndpoints,
    agent: ureq::Agent,
}

impl UsageService {
    pub fn new(monitor: Arc<AgentMonitor>, live_monitor: Arc<AgentMonitor>) -> Self {
        Self::with_options(monitor, live_monitor, UsageOptions::default())
    }

    pub fn with_options(monitor: Arc<AgentMonitor>, live_monitor: Arc<AgentMonitor>, options: UsageOptions) -> Self {
        UsageService {
            monitor,
            live_monitor,
            claude: ClaudeUsageClient::new(options.endpoints.claude_usage.clone(), options.read_credentials),
            endpoints: options.endpoints,
            agent: http_agent(),
        }
    }

    pub fn report(&self, force: bool) -> UsageReport {
        let mut providers = vec![self.claude_usage(force), self.codex_usage()];
        providers.extend(self.cursor_usage());
        let daily = self.monitor.daily_tokens(30.0 * 86400.0);
        UsageReport { providers, daily }
    }

    pub fn claude_usage(&self, force: bool) -> ProviderUsage {
        self.claude.usage(force)
    }

    pub fn codex_usage(&self) -> ProviderUsage {
        if !Paths::codex().exists() {
            return ProviderUsage::new(Harness::Codex, UsageState::NotInstalled);
        }
        let Some(snapshot) = self.live_monitor.codex_rate_limits() else {
            return ProviderUsage::new(Harness::Codex, UsageState::NoData);
        };
        ProviderUsage::new(Harness::Codex, UsageState::Ok)
            .with_plan(snapshot.plan)
            .with_windows(snapshot.windows, Some(snapshot.observed_at))
            .rolled_over(now())
    }

    pub fn cursor_usage(&self) -> Option<ProviderUsage> {
        cursor_usage(&self.agent, &self.endpoints)
    }

    pub fn forget_claude_credentials(&self) {
        self.claude.forget_credentials();
    }
}

pub fn cursor_usage(agent: &ureq::Agent, endpoints: &UsageEndpoints) -> Option<ProviderUsage> {
    if !cursor_auth::is_installed() {
        return None;
    }
    let failed = |message: String| Some(ProviderUsage::new(Harness::Cursor, UsageState::Failed(message)));
    let Some((token, user)) = cursor_auth::usable_token().and_then(|token| cursor_auth::user_id(&token).map(|user| (token, user)))
    else {
        return failed(tr("Cursor is signed out (or its session expired): open Cursor to sign in again."));
    };
    let cookie = format!("WorkosCursorSessionToken={user}%3A%3A{token}");
    let headers = [("Cookie", cookie.as_str()), ("Accept", "application/json")];
    let summary = match http_get(agent, &endpoints.cursor_summary, &headers) {
        Ok(response) => response,
        Err(error) => return failed(trf!("Network unavailable: %@", error)),
    };
    if summary.status == 401 || summary.status == 403 {
        return failed(tr("Cursor rejected the session: sign in again in Cursor."));
    }
    if summary.status == 200 {
        if let Some((plan, windows)) = parse_cursor_summary(&summary.body).filter(|(_, windows)| !windows.is_empty()) {
            return Some(ProviderUsage::new(Harness::Cursor, UsageState::Ok).with_plan(plan).with_windows(windows, Some(now())));
        }
    }
    let legacy = match http_get(agent, &format!("{}?user={user}", endpoints.cursor_legacy), &headers) {
        Ok(response) => response,
        Err(error) => return failed(trf!("Network unavailable: %@", error)),
    };
    if legacy.status != 200 {
        return failed(trf!("HTTP %d response from Cursor.", i64::from(legacy.status)));
    }
    let windows = parse_cursor_windows(&legacy.body);
    let state = if windows.is_empty() { UsageState::NoData } else { UsageState::Ok };
    Some(ProviderUsage::new(Harness::Cursor, state).with_windows(windows, Some(now())))
}

fn json_object(data: &[u8]) -> Option<Map<String, Value>> {
    match serde_json::from_slice(data).ok()? {
        Value::Object(map) => Some(map),
        _ => None,
    }
}

fn clamp_percent(value: f64) -> f64 {
    value.clamp(0.0, 100.0)
}

pub fn parse_cursor_summary(data: &[u8]) -> Option<(Option<String>, Vec<RateWindow>)> {
    let json = Value::Object(json_object(data)?);
    let reset = parse_date(json.get("billingCycleEnd"));
    let individual = json.get("individualUsage");
    let plan = individual.and_then(|value| value.get("plan"));
    let number = |dict: Option<&Value>, key: &str| dict.and_then(|dict| get_f64(dict, key));
    let ratio = |dict: Option<&Value>| {
        let used = number(dict, "used")?;
        let limit = number(dict, "limit")?;
        (limit > 0.0).then(|| used / limit * 100.0)
    };
    let auto = number(plan, "autoPercentUsed");
    let api = number(plan, "apiPercentUsed");
    let averaged = match (auto, api) {
        (Some(auto), Some(api)) => Some((auto + api) / 2.0),
        _ => api.or(auto),
    };
    let plan_percent = number(plan, "totalPercentUsed")
        .or(averaged)
        .or_else(|| ratio(plan))
        .or_else(|| ratio(individual.and_then(|value| value.get("overall"))))
        .or_else(|| ratio(json.get("teamUsage").and_then(|value| value.get("pooled"))));
    let mut windows = Vec::new();
    if let Some(percent) = plan_percent {
        windows.push(RateWindow { label: tr("Monthly plan"), used_percent: clamp_percent(percent), resets_at: reset, window_minutes: None });
    }
    if let Some(on_demand) = ratio(individual.and_then(|value| value.get("onDemand"))) {
        windows.push(RateWindow { label: tr("On-demand"), used_percent: clamp_percent(on_demand), resets_at: reset, window_minutes: None });
    }
    Some((get_str(&json, "membershipType").map(str::to_string), windows))
}

pub fn parse_cursor_windows(data: &[u8]) -> Vec<RateWindow> {
    let Some(json) = json_object(data) else { return Vec::new() };
    let reset = parse_date(json.get("startOfMonth")).and_then(|start| {
        start.with_timezone(&Local).checked_add_months(Months::new(1)).map(|date| date.with_timezone(&chrono::Utc))
    });
    let mut keys: Vec<&String> = json.keys().collect();
    keys.sort();
    keys.into_iter()
        .filter_map(|key| {
            let model = json.get(key)?;
            let used = get_f64(model, "numRequests")?;
            let max = get_f64(model, "maxRequestUsage")?;
            (max > 0.0).then(|| RateWindow {
                label: trf!("%@ requests", key),
                used_percent: (used / max * 100.0).min(100.0),
                resets_at: reset,
                window_minutes: None,
            })
        })
        .collect()
}

const CLAUDE_WINDOW_ORDER: [&str; 5] = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_oauth_apps"];

fn claude_window_label(key: &str) -> String {
    match key {
        "five_hour" => tr("5 h"),
        "seven_day" => tr("Week"),
        "seven_day_opus" => tr("Week · Opus"),
        "seven_day_sonnet" => tr("Week · Sonnet"),
        "seven_day_oauth_apps" => tr("Week · Apps"),
        other => other.replace('_', " "),
    }
}

pub fn parse_claude_windows(data: &[u8]) -> Vec<RateWindow> {
    let Some(json) = json_object(data) else { return Vec::new() };
    let rank = |key: &str| CLAUDE_WINDOW_ORDER.iter().position(|known| *known == key).unwrap_or(99);
    let mut keys: Vec<&String> = json.keys().collect();
    keys.sort_by(|a, b| (rank(a), a.as_str()).cmp(&(rank(b), b.as_str())));
    keys.into_iter()
        .filter_map(|key| {
            let window = json.get(key)?;
            let utilization = get_f64(window, "utilization")?;
            let minutes = if key == "five_hour" {
                Some(300)
            } else if key.starts_with("seven_day") {
                Some(10080)
            } else {
                None
            };
            Some(RateWindow {
                label: claude_window_label(key),
                used_percent: utilization,
                resets_at: parse_date(window.get("resets_at")),
                window_minutes: minutes,
            })
        })
        .collect()
}

pub fn decode_credentials(data: &[u8]) -> Option<ClaudeCredentials> {
    let json: Value = serde_json::from_slice(data).ok()?;
    let oauth = json.get("claudeAiOauth")?.as_object()?;
    let token = oauth.get("accessToken")?.as_str()?;
    Some(ClaudeCredentials {
        access_token: token.to_string(),
        expires_at: parse_date(oauth.get("expiresAt")),
        subscription: oauth.get("subscriptionType").and_then(Value::as_str).map(str::to_string),
    })
}

pub fn credentials_file() -> PathBuf {
    Paths::claude().join(".credentials.json")
}

pub fn read_credentials_file() -> KeychainResult {
    match std::fs::read(credentials_file()) {
        Ok(data) if !data.iter().all(u8::is_ascii_whitespace) => KeychainResult::Found(data),
        _ => KeychainResult::Missing,
    }
}

pub fn read_claude_credentials() -> KeychainResult {
    #[cfg(target_os = "macos")]
    {
        match read_keychain(KEYCHAIN_SERVICE) {
            KeychainResult::Missing => read_credentials_file(),
            other => other,
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        read_credentials_file()
    }
}

pub fn read_keychain(service: &str) -> KeychainResult {
    let mut command = std::process::Command::new("/usr/bin/security");
    command.args(["find-generic-password", "-s", service, "-w"]);
    match run_with_deadline(&mut command, Duration::from_secs(10), Duration::from_millis(50)) {
        ProcessOutcome::Exited { code: Some(0), stdout } => {
            let trimmed = stdout.trim();
            if trimmed.is_empty() {
                KeychainResult::Missing
            } else {
                KeychainResult::Found(trimmed.as_bytes().to_vec())
            }
        }
        ProcessOutcome::Exited { code: Some(44), .. } => KeychainResult::Missing,
        _ => KeychainResult::Blocked,
    }
}
