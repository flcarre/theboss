use std::collections::HashMap;

use chrono::{Local, Utc};
use serde::{Deserialize, Serialize};

use crate::localization::tr;
use crate::models::{DailyTokens, Timestamp};
use crate::store::Store;
use crate::util::day_key;

pub const DEFAULT_DAYS: usize = 28;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DayStat {
    pub day: String,
    pub prompts: i64,
    pub corrections: i64,
    pub tokens: i64,
}

impl DayStat {
    pub fn correction_rate(&self) -> f64 {
        if self.prompts == 0 {
            0.0
        } else {
            self.corrections as f64 / self.prompts as f64
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Trend {
    Improving { delta: f64 },
    Degrading { delta: f64 },
    Stable,
    NotEnoughData,
}

impl Trend {
    pub fn label(&self) -> String {
        match self {
            Trend::Improving { .. } => tr("Your setup is improving"),
            Trend::Degrading { .. } => tr("Your setup is getting worse"),
            Trend::Stable => tr("Your setup is stable"),
            Trend::NotEnoughData => tr("Not enough data yet"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AnalyticsReport {
    pub days: Vec<DayStat>,
    pub trend: Trend,
    pub corrections_this_week: i64,
    pub prompts_this_week: i64,
}

pub fn start_of_local_day(date: Timestamp) -> Timestamp {
    let local = date.with_timezone(&Local);
    local
        .date_naive()
        .and_hms_opt(0, 0, 0)
        .and_then(|midnight| midnight.and_local_timezone(Local).earliest())
        .map(|midnight| midnight.with_timezone(&Utc))
        .unwrap_or(date)
}

pub fn build(store: &Store, daily: &[DailyTokens], days: usize, now: Timestamp) -> AnalyticsReport {
    let count = days;
    let since = start_of_local_day(now - chrono::Duration::seconds((count as i64 - 1) * 86400));
    let stats = store.daily_prompt_stats(since);
    let mut tokens_by_day: HashMap<&str, i64> = HashMap::new();
    for entry in daily {
        *tokens_by_day.entry(entry.day.as_str()).or_default() += entry.tokens.total();
    }
    let days: Vec<DayStat> = (0..count)
        .map(|offset| {
            let key = day_key(since + chrono::Duration::seconds(offset as i64 * 86400 + 3600));
            let (prompts, corrections) = stats.get(&key).copied().unwrap_or((0, 0));
            let tokens = tokens_by_day.get(key.as_str()).copied().unwrap_or(0);
            DayStat { day: key, prompts, corrections, tokens }
        })
        .collect();
    let recent_start = days.len().saturating_sub(7);
    let recent = &days[recent_start..];
    let previous = &days[recent_start.saturating_sub(7)..recent_start];
    AnalyticsReport {
        trend: trend(recent, previous),
        corrections_this_week: recent.iter().map(|day| day.corrections).sum(),
        prompts_this_week: recent.iter().map(|day| day.prompts).sum(),
        days,
    }
}

pub fn trend(recent: &[DayStat], previous: &[DayStat]) -> Trend {
    let recent_prompts: i64 = recent.iter().map(|day| day.prompts).sum();
    let previous_prompts: i64 = previous.iter().map(|day| day.prompts).sum();
    if recent_prompts < 10 || previous_prompts < 10 {
        return Trend::NotEnoughData;
    }
    let recent_rate = recent.iter().map(|day| day.corrections).sum::<i64>() as f64 / recent_prompts as f64;
    let previous_rate = previous.iter().map(|day| day.corrections).sum::<i64>() as f64 / previous_prompts as f64;
    let delta = recent_rate - previous_rate;
    if delta <= -0.02 {
        Trend::Improving { delta: -delta }
    } else if delta >= 0.02 {
        Trend::Degrading { delta }
    } else {
        Trend::Stable
    }
}
