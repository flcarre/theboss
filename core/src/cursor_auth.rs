use std::path::{Path, PathBuf};

use base64::alphabet;
use base64::engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig};
use base64::Engine;
use rusqlite::{Connection, OpenFlags};
use serde_json::{Map, Value};

use crate::models::Timestamp;
use crate::paths::Paths;
use crate::util::{from_unix_seconds, now};

const JWT_ENGINE: GeneralPurpose = GeneralPurpose::new(
    &alphabet::URL_SAFE,
    GeneralPurposeConfig::new().with_decode_padding_mode(DecodePaddingMode::Indifferent).with_decode_allow_trailing_bits(true),
);

pub fn app_database() -> PathBuf {
    Paths::config_dir().join("Cursor/User/globalStorage/state.vscdb")
}

pub fn agent_auth_files() -> Vec<PathBuf> {
    vec![Paths::home().join(".config/cursor/auth.json"), Paths::cursor().join("auth.json")]
}

pub fn is_installed() -> bool {
    app_database().exists() || agent_auth_files().iter().any(|path| path.exists())
}

pub fn usable_token() -> Option<String> {
    std::iter::once(access_token(&app_database()))
        .chain(agent_auth_files().iter().map(|path| agent_token(path)))
        .flatten()
        .find(|token| is_usable(token))
}

pub fn access_token(database: &Path) -> Option<String> {
    if !database.exists() {
        return None;
    }
    let connection = Connection::open_with_flags(database, OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX).ok()?;
    let bytes = connection
        .query_row("SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'", [], |row| {
            Ok(row.get_ref(0)?.as_bytes().map(<[u8]>::to_vec).ok())
        })
        .ok()??;
    decode(&bytes)
}

pub fn agent_token(path: &Path) -> Option<String> {
    let data = std::fs::read(path).ok()?;
    let json: Value = serde_json::from_slice(&data).ok()?;
    let token = json.get("accessToken")?.as_str()?;
    (!token.is_empty()).then(|| token.to_string())
}

pub fn decode(data: &[u8]) -> Option<String> {
    let looks_utf16 = data.len() >= 4 && data.len().is_multiple_of(2) && data.iter().skip(1).step_by(2).all(|byte| *byte == 0);
    let text = if looks_utf16 {
        let units: Vec<u16> = data.as_chunks::<2>().0.iter().map(|pair| u16::from_le_bytes(*pair)).collect();
        String::from_utf16(&units).ok()
    } else {
        String::from_utf8(data.to_vec()).ok()
    };
    let token = text.as_deref().unwrap_or("").trim_matches(['"', ' ', '\n', '\0']).to_string();
    (!token.is_empty()).then_some(token)
}

pub fn claims(token: &str) -> Option<Map<String, Value>> {
    let parts: Vec<&str> = token.split('.').filter(|part| !part.is_empty()).collect();
    if parts.len() < 2 {
        return None;
    }
    let payload: String = parts[1]
        .chars()
        .filter(|c| *c != '=')
        .map(|c| match c {
            '+' => '-',
            '/' => '_',
            other => other,
        })
        .collect();
    let data = JWT_ENGINE.decode(payload).ok()?;
    match serde_json::from_slice(&data).ok()? {
        Value::Object(map) => Some(map),
        _ => None,
    }
}

pub fn is_usable(token: &str) -> bool {
    is_usable_at(token, now())
}

pub fn is_usable_at(token: &str, now: Timestamp) -> bool {
    let Some(claims) = claims(token) else { return false };
    if user_id(token).is_none() {
        return false;
    }
    let Some(exp) = claims.get("exp").and_then(Value::as_f64) else { return true };
    from_unix_seconds(exp) > now + chrono::Duration::seconds(60)
}

pub fn user_id(token: &str) -> Option<String> {
    let claims = claims(token)?;
    let sub = claims.get("sub")?.as_str()?;
    sub.split('|').rfind(|part| !part.is_empty()).map(str::to_string)
}
