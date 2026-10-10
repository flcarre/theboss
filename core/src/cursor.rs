use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use md5::{Digest, Md5};
use rusqlite::types::ValueRef;
use rusqlite::{Connection, OpenFlags};
use serde_json::Value;

use crate::models::{AgentSession, AgentStatus, Harness};
use crate::paths::Paths;
use crate::transcript::{cutoff, path_string, DEFAULT_RECENT_WINDOW};
use crate::trf;
use crate::util::{modified, seconds_since};

const STORE_FILE: &str = "store.db";
const STORE_WAL_FILE: &str = "store.db-wal";
const WORKING_WINDOW: f64 = 20.0;
const LIVE_WINDOW: f64 = 600.0;
const PLACEHOLDER_NAMES: &[&str] = &["New Agent", "New Chat"];

#[derive(Debug, Default, Clone, Copy)]
pub struct CursorSource;

impl CursorSource {
    pub fn new() -> Self {
        CursorSource
    }

    pub fn chats_dir(&self) -> PathBuf {
        Paths::cursor().join("chats")
    }

    pub fn projects_dir(&self) -> PathBuf {
        Paths::cursor().join("projects")
    }

    pub fn sessions(&self, known_directories: &[String]) -> Vec<AgentSession> {
        self.sessions_within(DEFAULT_RECENT_WINDOW, known_directories)
    }

    pub fn sessions_within(&self, recent_window: f64, known_directories: &[String]) -> Vec<AgentSession> {
        let cutoff = cutoff(recent_window);
        let mut workspaces: Option<HashMap<String, String>> = None;
        let mut result = Vec::new();
        let stores = walkdir::WalkDir::new(self.chats_dir())
            .into_iter()
            .filter_map(Result::ok)
            .filter(|entry| entry.file_name() == STORE_FILE)
            .map(walkdir::DirEntry::into_path);
        for store in stores {
            let Some(folder) = store.parent() else { continue };
            let Some(modified) = [store.clone(), folder.join(STORE_WAL_FILE)].iter().filter_map(modified).max() else {
                continue;
            };
            if modified < cutoff {
                continue;
            }
            let workspaces = workspaces.get_or_insert_with(|| self.workspace_index(known_directories));
            let idle = seconds_since(modified);
            let chat_id = file_name(folder);
            let hash = folder.parent().map(file_name).unwrap_or_default();
            let title = Self::chat_name(&store)
                .unwrap_or_else(|| trf!("Cursor chat %@", chat_id.chars().take(6).collect::<String>()));
            let status = if idle < WORKING_WINDOW { AgentStatus::Working } else { AgentStatus::Finished };
            let cwd = workspaces.get(&hash).cloned().unwrap_or_default();
            let mut session = AgentSession::new(Harness::Cursor, chat_id, title, cwd, status, modified);
            session.transcript_path = Some(path_string(&store));
            session.is_live = idle < LIVE_WINDOW;
            result.push(session);
        }
        result
    }

    pub fn workspace_index(&self, known_directories: &[String]) -> HashMap<String, String> {
        let slugs: Vec<String> = std::fs::read_dir(self.projects_dir())
            .map(|entries| {
                entries.filter_map(Result::ok).map(|entry| entry.file_name().to_string_lossy().into_owned()).collect()
            })
            .unwrap_or_default();
        let candidates: HashSet<String> = known_directories
            .iter()
            .filter(|dir| !dir.is_empty())
            .cloned()
            .chain(slugs.iter().filter_map(|slug| Self::directory_from_slug(slug)))
            .collect();
        let mut index = HashMap::new();
        for path in candidates {
            index.insert(Self::workspace_hash(&path), path.clone());
            let toggled = match path.strip_suffix('/').or_else(|| path.strip_suffix('\\')) {
                Some(trimmed) => trimmed.to_string(),
                None => format!("{path}/"),
            };
            index.insert(Self::workspace_hash(&toggled), path);
        }
        index
    }

    pub fn workspace_hash(path: &str) -> String {
        Md5::digest(path.as_bytes()).iter().map(|byte| format!("{byte:02x}")).collect()
    }

    pub fn directory_from_slug(slug: &str) -> Option<String> {
        let parts: Vec<&str> = slug.split('-').collect();
        let first = parts.first().filter(|first| !first.is_empty())?;
        if cfg!(windows) {
            let is_drive = first.len() == 1 && first.chars().all(|c| c.is_ascii_alphabetic());
            if !is_drive {
                return None;
            }
            return search_slug(&parts, 1, format!("{}:", first.to_ascii_uppercase()), '\\');
        }
        search_slug(&parts, 1, format!("/{first}"), '/')
    }

    pub fn chat_name(database: &Path) -> Option<String> {
        let connection = Connection::open_with_flags(database, OpenFlags::SQLITE_OPEN_READ_ONLY).ok()?;
        let raw: Vec<u8> = connection
            .query_row("SELECT value FROM meta WHERE key = '0'", [], |row| {
                Ok(match row.get_ref(0)? {
                    ValueRef::Blob(bytes) | ValueRef::Text(bytes) => bytes.to_vec(),
                    ValueRef::Integer(int) => int.to_string().into_bytes(),
                    ValueRef::Real(real) => real.to_string().into_bytes(),
                    ValueRef::Null => Vec::new(),
                })
            })
            .ok()?;
        if raw.is_empty() {
            return None;
        }
        Self::name_from_meta(&raw)
    }

    pub fn name_from_meta(raw: &[u8]) -> Option<String> {
        let text = std::str::from_utf8(raw).map(str::trim).unwrap_or("");
        let decoded = Self::hex_decoded(text);
        let json = decoded.as_deref().unwrap_or(raw);
        let object: Value = serde_json::from_slice(json).ok().filter(Value::is_object)?;
        let name = object.get("name").or_else(|| object.get("title")).and_then(Value::as_str).unwrap_or("").trim();
        if name.is_empty() || PLACEHOLDER_NAMES.contains(&name) {
            return None;
        }
        Some(name.to_string())
    }

    pub fn hex_decoded(text: &str) -> Option<Vec<u8>> {
        if text.len() < 2 || !text.len().is_multiple_of(2) || !text.bytes().all(|b| b.is_ascii_hexdigit()) {
            return None;
        }
        (0..text.len()).step_by(2).map(|i| u8::from_str_radix(&text[i..i + 2], 16).ok()).collect()
    }
}

fn file_name(path: &Path) -> String {
    path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default()
}

fn search_slug(parts: &[&str], index: usize, path: String, separator: char) -> Option<String> {
    if index == parts.len() {
        return Path::new(&path).is_dir().then_some(path);
    }
    if Path::new(&path).is_dir() {
        if let Some(found) = search_slug(parts, index + 1, format!("{path}{separator}{}", parts[index]), separator) {
            return Some(found);
        }
    }
    search_slug(parts, index + 1, format!("{path}-{}", parts[index]), separator)
}
