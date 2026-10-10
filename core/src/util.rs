use std::path::Path;
use std::time::SystemTime;

use chrono::{DateTime, Local, NaiveDate, TimeZone, Utc};
use serde_json::Value;

use crate::models::Timestamp;

pub fn now() -> Timestamp {
    Utc::now()
}

pub fn parse_date(value: Option<&Value>) -> Option<Timestamp> {
    match value? {
        Value::String(s) => DateTime::parse_from_rfc3339(s).ok().map(|d| d.with_timezone(&Utc)),
        Value::Number(n) => {
            let number = n.as_f64()?;
            let seconds = if number > 1e12 { number / 1000.0 } else { number };
            Utc.timestamp_millis_opt((seconds * 1000.0) as i64).single()
        }
        _ => None,
    }
}

pub fn parse_date_str(value: &str) -> Option<Timestamp> {
    DateTime::parse_from_rfc3339(value).ok().map(|d| d.with_timezone(&Utc))
}

pub fn day_key(date: Timestamp) -> String {
    date.with_timezone(&Local).format("%Y-%m-%d").to_string()
}

pub fn day_date(key: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(key, "%Y-%m-%d").ok()
}

pub fn modified(path: impl AsRef<Path>) -> Option<Timestamp> {
    let time = std::fs::metadata(path).ok()?.modified().ok()?;
    Some(system_time(time))
}

pub fn system_time(time: SystemTime) -> Timestamp {
    DateTime::<Utc>::from(time)
}

pub fn unix_seconds(date: Timestamp) -> f64 {
    date.timestamp_millis() as f64 / 1000.0
}

pub fn from_unix_seconds(seconds: f64) -> Timestamp {
    Utc.timestamp_millis_opt((seconds * 1000.0) as i64).single().unwrap_or_default()
}

pub fn trim_spaces(text: &str) -> &str {
    text.trim_matches(|c: char| c.is_whitespace() && !matches!(c, '\n' | '\r' | '\u{0B}' | '\u{0C}' | '\u{85}' | '\u{2028}' | '\u{2029}'))
}

pub fn seconds_since(date: Timestamp) -> f64 {
    (now() - date).num_milliseconds() as f64 / 1000.0
}

pub fn is_process_alive(pid: u32) -> bool {
    use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, System};
    let mut system = System::new();
    let pid = Pid::from_u32(pid);
    system.refresh_processes_specifics(ProcessesToUpdate::Some(&[pid]), true, ProcessRefreshKind::nothing());
    system.process(pid).is_some()
}

pub enum ProcessOutcome {
    Exited { code: Option<i32>, stdout: String },
    TimedOut,
    FailedToStart(std::io::Error),
}

pub fn hide_console_window(command: &mut std::process::Command) -> &mut std::process::Command {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x0800_0000);
    }
    command
}

pub fn run_with_deadline(command: &mut std::process::Command, timeout: std::time::Duration, poll: std::time::Duration) -> ProcessOutcome {
    use std::io::Read;
    use std::process::Stdio;
    hide_console_window(command).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => return ProcessOutcome::FailedToStart(error),
    };
    let reader = child.stdout.take().map(|mut stdout| {
        std::thread::spawn(move || {
            let mut bytes = Vec::new();
            let _ = stdout.read_to_end(&mut bytes);
            String::from_utf8_lossy(&bytes).into_owned()
        })
    });
    let deadline = std::time::Instant::now() + timeout;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let stdout = reader.and_then(|handle| handle.join().ok()).unwrap_or_default();
                return ProcessOutcome::Exited { code: status.code(), stdout };
            }
            Ok(None) if std::time::Instant::now() < deadline => std::thread::sleep(poll),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return ProcessOutcome::TimedOut;
            }
        }
    }
}

pub fn last_path_component(path: &str) -> String {
    path.trim_end_matches(['/', '\\'])
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or("")
        .to_string()
}

pub fn truncated(text: &str, limit: usize) -> String {
    if text.chars().count() > limit {
        let mut out: String = text.chars().take(limit.saturating_sub(1)).collect();
        out.push('…');
        out
    } else {
        text.to_string()
    }
}

pub fn single_line(text: &str) -> String {
    text.lines().map(str::trim).filter(|l| !l.is_empty()).collect::<Vec<_>>().join(" ")
}

pub fn get_str<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key)?.as_str()
}

pub fn get_i64(value: &Value, key: &str) -> i64 {
    value.get(key).and_then(Value::as_i64).unwrap_or(0)
}

pub fn get_f64(value: &Value, key: &str) -> Option<f64> {
    value.get(key)?.as_f64()
}
