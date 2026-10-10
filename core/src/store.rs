use std::collections::HashMap;
use std::path::Path;
use std::sync::{Mutex, MutexGuard};

use rusqlite::{params, Connection};
use serde_json::{Map, Value};

use crate::corrections;
use crate::models::{Harness, Timestamp, UserPrompt};
use crate::paths::Paths;
use crate::suggestions::Suggestion;
use crate::usage::{ProviderUsage, UsageState};
use crate::util::{day_key, from_unix_seconds, now, unix_seconds};

pub const APPLE_REFERENCE_EPOCH: f64 = 978_307_200.0;

const SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS suggestions (
        id TEXT PRIMARY KEY, status TEXT NOT NULL, updated_at REAL NOT NULL, payload BLOB NOT NULL)",
    "CREATE TABLE IF NOT EXISTS prompts (
        harness TEXT NOT NULL, session_id TEXT NOT NULL, cwd TEXT NOT NULL, ts REAL NOT NULL,
        text TEXT NOT NULL, is_correction INTEGER NOT NULL,
        PRIMARY KEY (harness, session_id, ts, text))",
    "CREATE TABLE IF NOT EXISTS usage_samples (ts REAL NOT NULL, harness TEXT NOT NULL, label TEXT NOT NULL, used REAL NOT NULL)",
    "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
];

pub struct Store {
    connection: Mutex<Option<Connection>>,
}

impl Store {
    pub fn open(path: &Path) -> Store {
        let connection = Connection::open(path).ok();
        if let Some(connection) = &connection {
            let _ = connection.query_row("PRAGMA journal_mode=WAL", [], |_| Ok(()));
            for statement in SCHEMA {
                let _ = connection.execute(statement, []);
            }
        }
        Store { connection: Mutex::new(connection) }
    }

    pub fn open_default() -> Store {
        Store::open(&Paths::app_data().join("boss.sqlite"))
    }

    fn lock(&self) -> MutexGuard<'_, Option<Connection>> {
        self.connection.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub fn saved_suggestions(&self) -> Vec<Suggestion> {
        let guard = self.lock();
        let Some(connection) = guard.as_ref() else { return Vec::new() };
        let Ok(mut statement) = connection.prepare("SELECT payload FROM suggestions") else { return Vec::new() };
        let Ok(rows) = statement.query_map([], |row| Ok(row.get_ref(0)?.as_bytes().map(<[u8]>::to_vec).ok())) else {
            return Vec::new();
        };
        rows.filter_map(Result::ok).flatten().filter_map(|payload| decode_suggestion(&payload)).collect()
    }

    pub fn save(&self, suggestion: &Suggestion) {
        let Ok(payload) = serde_json::to_vec(suggestion) else { return };
        let guard = self.lock();
        let Some(connection) = guard.as_ref() else { return };
        let _ = connection.execute(
            "INSERT OR REPLACE INTO suggestions (id, status, updated_at, payload) VALUES (?, ?, ?, ?)",
            params![suggestion.id, suggestion.status.raw(), unix_seconds(now()), payload],
        );
    }

    pub fn record_prompts(&self, prompts: &[UserPrompt]) {
        let mut guard = self.lock();
        let Some(connection) = guard.as_mut() else { return };
        let Ok(transaction) = connection.transaction() else { return };
        for prompt in prompts {
            let is_correction = corrections::detect(prompt).is_some();
            let _ = transaction.execute(
                "INSERT OR IGNORE INTO prompts (harness, session_id, cwd, ts, text, is_correction) VALUES (?, ?, ?, ?, ?, ?)",
                params![
                    prompt.harness.raw(),
                    prompt.session_id,
                    prompt.cwd,
                    unix_seconds(prompt.timestamp.unwrap_or_else(now)),
                    prompt.text,
                    i64::from(is_correction),
                ],
            );
        }
        let _ = transaction.commit();
    }

    pub fn daily_prompt_stats(&self, since: Timestamp) -> HashMap<String, (i64, i64)> {
        let mut result: HashMap<String, (i64, i64)> = HashMap::new();
        let guard = self.lock();
        let Some(connection) = guard.as_ref() else { return result };
        let Ok(mut statement) = connection.prepare("SELECT ts, is_correction FROM prompts WHERE ts >= ?") else {
            return result;
        };
        let Ok(rows) =
            statement.query_map(params![unix_seconds(since)], |row| Ok((row.get::<_, f64>(0)?, row.get::<_, i64>(1)?)))
        else {
            return result;
        };
        for (ts, correction) in rows.filter_map(Result::ok) {
            let entry = result.entry(day_key(from_unix_seconds(ts))).or_insert((0, 0));
            entry.0 += 1;
            entry.1 += i64::from(correction == 1);
        }
        result
    }

    pub fn search_prompts(&self, text: &str, limit: usize) -> Vec<UserPrompt> {
        let guard = self.lock();
        let Some(connection) = guard.as_ref() else { return Vec::new() };
        let Ok(mut statement) = connection
            .prepare("SELECT harness, session_id, cwd, ts, text FROM prompts WHERE text LIKE ? ORDER BY ts DESC LIMIT ?")
        else {
            return Vec::new();
        };
        let pattern = format!("%{text}%");
        let Ok(rows) = statement.query_map(params![pattern, limit as i64], |row| {
            Ok(UserPrompt {
                harness: Harness::from_raw(&row.get::<_, String>(0)?).unwrap_or(Harness::Claude),
                session_id: row.get(1)?,
                cwd: row.get(2)?,
                text: row.get(4)?,
                timestamp: Some(from_unix_seconds(row.get(3)?)),
                previous_assistant: None,
            })
        }) else {
            return Vec::new();
        };
        rows.filter_map(Result::ok).collect()
    }

    pub fn record_usage(&self, providers: &[ProviderUsage]) {
        let timestamp = unix_seconds(now());
        let guard = self.lock();
        let Some(connection) = guard.as_ref() else { return };
        for provider in providers.iter().filter(|provider| provider.state == UsageState::Ok) {
            for window in &provider.windows {
                let _ = connection.execute(
                    "INSERT INTO usage_samples (ts, harness, label, used) VALUES (?, ?, ?, ?)",
                    params![timestamp, provider.harness.raw(), window.label, window.used_percent],
                );
            }
        }
    }

    pub fn setting(&self, key: &str) -> Option<String> {
        let guard = self.lock();
        let connection = guard.as_ref()?;
        connection.query_row("SELECT value FROM settings WHERE key = ?", params![key], |row| row.get(0)).ok()
    }

    pub fn set_setting(&self, key: &str, value: &str) {
        let guard = self.lock();
        let Some(connection) = guard.as_ref() else { return };
        let _ = connection.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", params![key, value]);
    }
}

pub fn decode_suggestion(payload: &[u8]) -> Option<Suggestion> {
    if let Ok(suggestion) = serde_json::from_slice::<Suggestion>(payload) {
        return Some(suggestion);
    }
    let value: Value = serde_json::from_slice(payload).ok()?;
    serde_json::from_value(legacy_to_current(value)?).ok()
}

pub fn legacy_to_current(value: Value) -> Option<Value> {
    let Value::Object(mut object) = value else { return None };
    if let Some(created) = object.get("createdAt").and_then(legacy_date) {
        object.insert("createdAt".into(), created);
    }
    if let Some(Value::Array(evidence)) = object.get_mut("evidence") {
        for item in evidence.iter_mut().filter_map(Value::as_object_mut) {
            if let Some(date) = item.get("date").and_then(legacy_date) {
                item.insert("date".into(), date);
            }
        }
    }
    if let Some(operation) = object.get("operation").and_then(legacy_operation) {
        object.insert("operation".into(), operation);
    }
    Some(Value::Object(object))
}

fn legacy_date(value: &Value) -> Option<Value> {
    let seconds = value.as_f64()?;
    serde_json::to_value(from_unix_seconds(seconds + APPLE_REFERENCE_EPOCH)).ok()
}

fn legacy_operation(value: &Value) -> Option<Value> {
    let object = value.as_object()?;
    if object.contains_key("type") || object.len() != 1 {
        return None;
    }
    let (case, payload) = object.iter().next()?;
    let mut converted = Map::new();
    converted.insert("type".into(), Value::String(case.clone()));
    let unnamed = payload.get("_0").cloned();
    match case.as_str() {
        "appendRule" => {
            converted.insert("rule".into(), unnamed?);
        }
        "createFile" => {
            converted.insert("body".into(), unnamed?);
        }
        "removeLines" => {
            converted.insert("lines".into(), unnamed?);
        }
        "addFrontmatter" => {
            converted.insert("name".into(), payload.get("name")?.clone());
            converted.insert("description".into(), payload.get("description")?.clone());
        }
        _ => return None,
    }
    Some(Value::Object(converted))
}
