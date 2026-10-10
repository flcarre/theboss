use std::collections::{HashMap, HashSet};
use std::thread;
use std::time::Duration;

use boss_core::suggestions::{Suggestion, SuggestionEngine, SuggestionKind, SuggestionStatus};
use boss_core::{analytics, rule_writer, rules, tr, trf, AgentSession, AgentStatus};
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_notification::NotificationExt;

use crate::state::{Boss, SuggestionView};
use crate::tray;

const HISTORY_WINDOW: f64 = 30.0 * 86400.0;
const SESSIONS_EVERY: Duration = Duration::from_secs(2);
const USAGE_EVERY: Duration = Duration::from_secs(120);
const INSIGHTS_EVERY: Duration = Duration::from_secs(300);

pub fn start(app: &AppHandle) {
    let sessions_app = app.clone();
    thread::spawn(move || loop {
        refresh_sessions(&sessions_app);
        thread::sleep(SESSIONS_EVERY);
    });
    let usage_app = app.clone();
    thread::spawn(move || {
        refresh_usage(&usage_app, true);
        loop {
            thread::sleep(USAGE_EVERY);
            refresh_usage(&usage_app, false);
        }
    });
    let insights_app = app.clone();
    thread::spawn(move || loop {
        refresh_insights(&insights_app);
        thread::sleep(INSIGHTS_EVERY);
    });
}

pub fn emit_snapshot(app: &AppHandle) {
    let boss = app.state::<Boss>();
    let snapshot = boss.data().snapshot();
    if let Some(path) = std::env::var_os("BOSS_SNAPSHOT_OUT") {
        if let Ok(json) = serde_json::to_string_pretty(&snapshot) {
            let _ = std::fs::write(path, json);
        }
    }
    let _ = app.emit("snapshot", snapshot);
}

pub fn toast(app: &AppHandle, text: impl Into<String>) {
    let _ = app.emit("toast", text.into());
}

pub fn sound(app: &AppHandle, name: &str) {
    let _ = app.emit("sound", name.to_string());
}

fn window_focused(app: &AppHandle) -> bool {
    app.get_webview_window("main").and_then(|w| w.is_focused().ok()).unwrap_or(false)
}

fn notify(app: &AppHandle, title: &str, body: &str, sound_name: &str) {
    sound(app, sound_name);
    let enabled = app.state::<Boss>().data().settings.notifications;
    if !enabled || window_focused(app) {
        return;
    }
    let _ = app.notification().builder().title(title).body(body).show();
}

pub fn refresh_sessions(app: &AppHandle) {
    let boss = app.state::<Boss>();
    let sessions = boss.monitor.sessions();
    let mut newly_waiting: Vec<AgentSession> = Vec::new();
    let mut newly_done: Vec<AgentSession> = Vec::new();
    let changed = {
        let mut data = boss.data();
        for session in &sessions {
            if let Some(previous) = data.previous_status.get(&session.id).copied() {
                if previous != session.status {
                    if session.status == AgentStatus::NeedsApproval {
                        newly_waiting.push(session.clone());
                    }
                    if session.status == AgentStatus::Finished && previous == AgentStatus::Working {
                        newly_done.push(session.clone());
                    }
                }
            }
            data.previous_status.insert(session.id.clone(), session.status);
        }
        let changed = data.sessions != sessions;
        data.sessions = sessions;
        changed
    };
    if !changed {
        return;
    }
    tray::update(app);
    emit_snapshot(app);
    for session in newly_waiting {
        notify(app, &trf!("%@ needs your approval", session.harness.display_name()), &session.title, "glass");
        toast(app, trf!("%@: a robot needs your approval", &session.project_name));
    }
    for session in newly_done {
        notify(app, &trf!("%@ is done", session.harness.display_name()), &session.title, "tink");
    }
}

pub fn refresh_usage(app: &AppHandle, force: bool) {
    let boss = app.state::<Boss>();
    if boss.data().usage.is_none() {
        let codex = boss.usage.codex_usage();
        let mut data = boss.data();
        if data.usage.is_none() {
            data.usage = Some(boss_core::usage::UsageReport { providers: vec![codex], daily: Vec::new() });
        }
        drop(data);
        emit_snapshot(app);
    }
    let report = boss.usage.report(force);
    boss.store.record_usage(&report.providers);
    let insights_ready = boss.data().insights_ready;
    let analytics = insights_ready.then(|| analytics::build(&boss.store, &report.daily, 28, boss_core::util::now()));
    {
        let mut data = boss.data();
        data.usage = Some(report);
        if let Some(analytics) = analytics {
            data.analytics = Some(analytics);
        }
    }
    emit_snapshot(app);
}

pub fn refresh_insights(app: &AppHandle) {
    let boss = app.state::<Boss>();
    let current_sessions = {
        let mut data = boss.data();
        if data.insights_running {
            return;
        }
        data.insights_running = true;
        data.sessions.clone()
    };
    let prompts = boss.history.prompts(HISTORY_WINDOW);
    boss.store.record_prompts(&prompts);
    let sessions = if current_sessions.is_empty() { boss.history.sessions() } else { current_sessions };
    let fresh = SuggestionEngine.suggestions(&prompts, &sessions);
    let saved = boss.store.saved_suggestions();
    let projects: Vec<String> = sessions.iter().map(|s| s.cwd.clone()).collect();
    let rule_items = rules::scan(&projects);
    let daily = boss.history.daily_tokens(HISTORY_WINDOW);
    let report = analytics::build(&boss.store, &daily, 28, boss_core::util::now());

    let saved_by_id: HashMap<&str, &Suggestion> = saved.iter().map(|s| (s.id.as_str(), s)).collect();
    let fresh_ids: HashSet<&str> = fresh.iter().map(|s| s.id.as_str()).collect();
    let mut merged: Vec<Suggestion> = fresh
        .iter()
        .map(|suggestion| {
            let mut copy = suggestion.clone();
            if let Some(saved) = saved_by_id.get(suggestion.id.as_str()) {
                copy.status = saved.status;
                if let Some(refined) = &saved.refined_rule {
                    copy.refine(refined);
                }
            }
            copy
        })
        .collect();
    merged.extend(saved.iter().filter(|s| !fresh_ids.contains(s.id.as_str()) && s.status != SuggestionStatus::New).cloned());
    merged.sort_by(|a, b| b.created_at.cmp(&a.created_at).then_with(|| a.id.cmp(&b.id)));
    let views: Vec<SuggestionView> = merged.into_iter().map(SuggestionView::of).collect();

    let (added_title, to_refine) = {
        let mut data = boss.data();
        let before: HashSet<String> = data.open_suggestions().map(|s| s.id.clone()).collect();
        data.suggestions = views;
        data.rules = rule_items;
        data.analytics = Some(report);
        let added_title = data.open_suggestions().find(|s| !before.contains(&s.id)).map(|s| s.title.clone());
        let was_ready = data.insights_ready;
        data.insights_ready = true;
        data.insights_running = false;
        let to_refine: Vec<String> = if data.settings.auto_refine {
            data.open_suggestions()
                .filter(|s| s.kind == SuggestionKind::LearnedRule && s.refined_rule.is_none())
                .map(|s| s.id.clone())
                .collect()
        } else {
            Vec::new()
        };
        (added_title.filter(|_| was_ready), to_refine)
    };
    tray::update(app);
    emit_snapshot(app);
    if let Some(title) = added_title {
        notify(app, &tr("New mail"), &title, "pop");
    }
    for id in to_refine {
        refine(app, id);
    }
}

pub fn spawn_insights(app: &AppHandle) {
    let app = app.clone();
    thread::spawn(move || refresh_insights(&app));
}

pub fn spawn_usage(app: &AppHandle, force: bool) {
    let app = app.clone();
    thread::spawn(move || refresh_usage(&app, force));
}

pub fn refine(app: &AppHandle, id: String) {
    let boss = app.state::<Boss>();
    let suggestion = {
        let mut data = boss.data();
        if data.refining.contains(&id) {
            return;
        }
        let Some(suggestion) = data.suggestion(&id) else { return };
        data.refining.insert(id.clone());
        suggestion
    };
    emit_snapshot(app);
    let app = app.clone();
    thread::spawn(move || {
        let result = rule_writer::refine(&suggestion, Duration::from_secs(90));
        let boss = app.state::<Boss>();
        let message = {
            let mut data = boss.data();
            data.refining.remove(&id);
            match result {
                Ok(Some(rule)) => match data.suggestion(&id) {
                    Some(mut current) => {
                        current.refine(&rule);
                        boss.store.save(&current);
                        data.replace_suggestion(current);
                        Some(tr("Rule rewritten by Claude"))
                    }
                    None => None,
                },
                Ok(None) => Some(tr("Claude sees no general rule here")),
                Err(error) => Some(error),
            }
        };
        emit_snapshot(&app);
        if let Some(message) = message {
            toast(&app, message);
        }
    });
}

pub fn repair_claude(app: &AppHandle) {
    let boss = app.state::<Boss>();
    {
        let mut data = boss.data();
        if data.repairing_claude {
            return;
        }
        data.repairing_claude = true;
    }
    emit_snapshot(app);
    let app = app.clone();
    thread::spawn(move || {
        let ok = rule_writer::refresh_claude_login(Duration::from_secs(60));
        let boss = app.state::<Boss>();
        boss.usage.forget_claude_credentials();
        boss.data().repairing_claude = false;
        toast(&app, if ok { tr("Claude token refreshed") } else { tr("Claude Code could not reconnect: run `claude auth login`") });
        refresh_usage(&app, true);
    });
}
