use std::collections::HashMap;
use std::sync::{LazyLock, RwLock};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum AppLanguage {
    #[default]
    #[serde(rename = "en")]
    English,
    #[serde(rename = "fr")]
    French,
}

static FRENCH: LazyLock<HashMap<String, String>> =
    LazyLock::new(|| serde_json::from_str(include_str!("../../shared/fr.json")).expect("shared/fr.json is valid"));

static LANGUAGE: RwLock<AppLanguage> = RwLock::new(AppLanguage::English);

pub fn set_language(language: AppLanguage) {
    *LANGUAGE.write().unwrap() = language;
}

pub fn language() -> AppLanguage {
    *LANGUAGE.read().unwrap()
}

pub fn tr(key: &str) -> String {
    match language() {
        AppLanguage::French => FRENCH.get(key).cloned().unwrap_or_else(|| key.to_string()),
        AppLanguage::English => key.to_string(),
    }
}

pub enum Arg {
    Str(String),
    Int(i64),
}

impl From<&str> for Arg {
    fn from(value: &str) -> Self {
        Arg::Str(value.to_string())
    }
}

impl From<String> for Arg {
    fn from(value: String) -> Self {
        Arg::Str(value)
    }
}

impl From<&String> for Arg {
    fn from(value: &String) -> Self {
        Arg::Str(value.clone())
    }
}

impl From<i64> for Arg {
    fn from(value: i64) -> Self {
        Arg::Int(value)
    }
}

impl From<i32> for Arg {
    fn from(value: i32) -> Self {
        Arg::Int(value as i64)
    }
}

impl From<usize> for Arg {
    fn from(value: usize) -> Self {
        Arg::Int(value as i64)
    }
}

impl From<u16> for Arg {
    fn from(value: u16) -> Self {
        Arg::Int(value as i64)
    }
}

pub fn format(template: &str, args: &[Arg]) -> String {
    let mut out = String::with_capacity(template.len());
    let mut chars = template.chars().peekable();
    let mut next = 0;
    while let Some(c) = chars.next() {
        if c != '%' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('%') => out.push('%'),
            Some('@') | Some('d') => {
                match args.get(next) {
                    Some(Arg::Str(s)) => out.push_str(s),
                    Some(Arg::Int(i)) => out.push_str(&i.to_string()),
                    None => {}
                }
                next += 1;
            }
            Some(other) => {
                out.push('%');
                out.push(other);
            }
            None => out.push('%'),
        }
    }
    out
}

#[macro_export]
macro_rules! trf {
    ($key:expr, $($arg:expr),+ $(,)?) => {
        $crate::localization::format(&$crate::localization::tr($key), &[$($crate::localization::Arg::from($arg)),+])
    };
}
