use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use serde_json::Value;

const NEWLINE: u8 = 0x0A;
const QUOTE: u8 = 0x22;
const CAPTURE_MAX_BYTES: usize = 200;
pub const DEFAULT_CAPTURE_LIMIT: usize = 64;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct JsonlTail {
    offset: u64,
    size: u64,
}

impl JsonlTail {
    pub fn offset(&self) -> u64 {
        self.offset
    }

    pub fn size(&self) -> u64 {
        self.size
    }

    pub fn read_new_lines(&mut self, path: &Path) -> (Vec<Vec<u8>>, bool) {
        let Ok(metadata) = std::fs::metadata(path) else { return (Vec::new(), false) };
        let file_size = metadata.len();
        let mut reset = false;
        if file_size < self.offset {
            self.offset = 0;
            reset = true;
        }
        self.size = file_size;
        if file_size <= self.offset {
            return (Vec::new(), reset);
        }
        let Some(data) = read_from(path, self.offset) else { return (Vec::new(), reset) };
        let Some(last_newline) = data.iter().rposition(|&b| b == NEWLINE) else { return (Vec::new(), reset) };
        let complete = &data[..=last_newline];
        self.offset += complete.len() as u64;
        let lines = complete
            .split(|&b| b == NEWLINE)
            .filter(|line| !line.is_empty())
            .map(<[u8]>::to_vec)
            .collect();
        (lines, reset)
    }

    pub fn read_new_objects(&mut self, path: &Path) -> (Vec<Value>, bool) {
        let (lines, reset) = self.read_new_lines(path);
        (lines.iter().filter_map(|line| Self::object(line)).collect(), reset)
    }

    pub fn object(line: &[u8]) -> Option<Value> {
        serde_json::from_slice::<Value>(line).ok().filter(Value::is_object)
    }
}

fn read_from(path: &Path, offset: u64) -> Option<Vec<u8>> {
    let mut file = File::open(path).ok()?;
    file.seek(SeekFrom::Start(offset)).ok()?;
    let mut data = Vec::new();
    file.read_to_end(&mut data).ok()?;
    Some(data)
}

pub fn find_bytes(haystack: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if needle.is_empty() {
        return Some(from.min(haystack.len()));
    }
    let first = needle[0];
    let last_start = haystack.len().checked_sub(needle.len())?;
    let mut start = from;
    while start <= last_start {
        let offset = haystack[start..=last_start].iter().position(|&b| b == first)?;
        let candidate = start + offset;
        if &haystack[candidate..candidate + needle.len()] == needle {
            return Some(candidate);
        }
        start = candidate + 1;
    }
    None
}

pub fn contains_bytes(haystack: &[u8], needle: &str) -> bool {
    find_bytes(haystack, needle.as_bytes(), 0).is_some()
}

pub fn captures(haystack: &[u8], marker: &str, limit: usize) -> Vec<String> {
    let marker = marker.as_bytes();
    let mut result = Vec::new();
    let mut search_start = 0;
    while let Some(found) = find_bytes(haystack, marker, search_start) {
        let mut cursor = found + marker.len();
        let value_start = cursor;
        while cursor < haystack.len() && haystack[cursor] != QUOTE && cursor - value_start < CAPTURE_MAX_BYTES {
            cursor += 1;
        }
        if let Ok(value) = std::str::from_utf8(&haystack[value_start..cursor]) {
            result.push(value.to_string());
        }
        search_start = cursor;
        if result.len() >= limit {
            break;
        }
    }
    result
}

pub fn json_int(value: Option<&Value>) -> Option<i64> {
    let value = value?;
    if let Some(int) = value.as_i64() {
        return Some(int);
    }
    let float = value.as_f64()?;
    (float.fract() == 0.0 && float.abs() < i64::MAX as f64).then_some(float as i64)
}

pub fn int_or_zero(value: &Value, key: &str) -> i64 {
    json_int(value.get(key)).unwrap_or(0)
}

pub fn object_array(value: Option<&Value>) -> Option<&[Value]> {
    let items = value?.as_array()?;
    items.iter().all(Value::is_object).then_some(items.as_slice())
}

pub fn string_array(value: Option<&Value>) -> Option<Vec<&str>> {
    value?.as_array()?.iter().map(Value::as_str).collect()
}

pub fn object_field<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
    value.get(key).filter(|v| v.is_object())
}
