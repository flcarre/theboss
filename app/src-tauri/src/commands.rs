use boss_core::suggestions::SuggestionStatus;
use boss_core::{domain, launcher, trf, TranscriptMessage};
use serde::Serialize;
use tauri::{AppHandle, State};

use crate::state::{Boss, Settings, Snapshot};
use crate::{tray, workers};

#[derive(Serialize)]
pub struct FocusResult {
    opened: bool,
    command: String,
}

#[tauri::command]
pub fn snapshot(boss: State<'_, Boss>) -> Snapshot {
    boss.data().snapshot()
}

#[tauri::command]
pub async fn messages(boss: State<'_, Boss>, session_id: String) -> Result<Vec<TranscriptMessage>, String> {
    let session = boss.data().sessions.iter().find(|s| s.id == session_id).cloned();
    Ok(session.map(|s| boss.monitor.messages(&s)).unwrap_or_default())
}

#[tauri::command]
pub fn set_suggestion_status(app: AppHandle, boss: State<'_, Boss>, id: String, status: SuggestionStatus) -> Result<(), String> {
    let Some(mut suggestion) = boss.data().suggestion(&id) else {
        return Err(format!("Unknown suggestion {id}"));
    };
    if status == SuggestionStatus::Applied {
        suggestion
            .apply()
            .map_err(|error| trf!("Could not write %@: %@", suggestion.display_path(), error.to_string()))?;
    }
    suggestion.status = status;
    boss.store.save(&suggestion);
    boss.data().replace_suggestion(suggestion);
    tray::update(&app);
    workers::emit_snapshot(&app);
    Ok(())
}

#[tauri::command]
pub fn refine_suggestion(app: AppHandle, id: String) {
    workers::refine(&app, id);
}

#[tauri::command]
pub fn domain_projects(boss: State<'_, Boss>) -> Vec<String> {
    domain::projects(&boss.data().sessions)
}

#[tauri::command]
pub async fn domain_model(boss: State<'_, Boss>, root: String) -> Result<domain::DomainModel, String> {
    let intent = boss.store.setting(&format!("intent:{root}")).unwrap_or_default();
    let (sessions, suggestions) = {
        let data = boss.data();
        (data.sessions.clone(), data.suggestions.iter().map(|view| view.suggestion.clone()).collect::<Vec<_>>())
    };
    Ok(domain::build(&root, &intent, &sessions, &suggestions))
}

#[tauri::command]
pub fn save_intent(boss: State<'_, Boss>, root: String, intent: String) {
    boss.store.set_setting(&format!("intent:{root}"), &intent);
}

#[tauri::command]
pub async fn export_domain(boss: State<'_, Boss>, root: String) -> Result<String, String> {
    let model = domain_model(boss, root).await?;
    domain::export(&model).map_err(|error| trf!("Could not write: %@", error.to_string()))?;
    Ok(format!("{}/.boss/domain.md", model.name))
}

#[tauri::command]
pub fn save_settings(app: AppHandle, boss: State<'_, Boss>, settings: Settings) {
    let language_changed = {
        let mut data = boss.data();
        let changed = data.settings.language != settings.language;
        data.settings = settings.clone();
        changed
    };
    if let Ok(raw) = serde_json::to_string(&settings) {
        boss.store.set_setting("settings", &raw);
    }
    if language_changed {
        boss_core::localization::set_language(settings.language);
        tray::update(&app);
        workers::spawn_insights(&app);
        workers::spawn_usage(&app, true);
    }
    workers::emit_snapshot(&app);
}

#[tauri::command]
pub fn record_whip(app: AppHandle, boss: State<'_, Boss>) -> i64 {
    let count = {
        let mut data = boss.data();
        data.whip_count += 1;
        data.whip_count
    };
    boss.store.set_setting("whips", &count.to_string());
    workers::emit_snapshot(&app);
    count
}

#[tauri::command]
pub async fn focus_session(boss: State<'_, Boss>, session_id: String) -> Result<FocusResult, String> {
    let session = boss.data().sessions.iter().find(|s| s.id == session_id).cloned().ok_or_else(|| format!("Unknown session {session_id}"))?;
    let command = launcher::resume_command(&session);
    Ok(FocusResult { opened: launcher::focus(&session), command })
}

#[tauri::command]
pub fn open_claude_login() -> Result<(), String> {
    launcher::open_claude_login()
}

#[tauri::command]
pub fn repair_claude_usage(app: AppHandle) {
    workers::repair_claude(&app);
}

#[tauri::command]
pub fn refresh_usage(app: AppHandle, force: bool) {
    workers::spawn_usage(&app, force);
}

#[tauri::command]
pub fn rule_content(boss: State<'_, Boss>, path: String) -> Result<String, String> {
    let known = boss.data().rules.iter().any(|rule| rule.path == path);
    if !known {
        return Err(format!("Unknown rule file {path}"));
    }
    std::fs::read_to_string(&path).map_err(|error| error.to_string())
}
