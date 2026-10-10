use boss_core::{tr, trf, AgentSession, AgentStatus, Harness};
use tauri::image::Image;
use tauri::menu::{Menu, MenuBuilder, MenuItem, MenuItemBuilder, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, Wry};

use crate::state::Boss;

const TRAY_ID: &str = "main";
const LISTED_SESSIONS: usize = 6;

fn icon(alert: bool) -> Option<Image<'static>> {
    let bytes: &[u8] = if cfg!(target_os = "macos") {
        if alert { include_bytes!("../icons/tray-alert.png") } else { include_bytes!("../icons/tray.png") }
    } else {
        include_bytes!("../icons/32x32.png")
    };
    Image::from_bytes(bytes).ok()
}

pub fn install(app: &AppHandle) -> tauri::Result<()> {
    let mut builder = TrayIconBuilder::with_id(TRAY_ID)
        .tooltip("The Boss")
        .menu(&build_menu(app)?)
        .show_menu_on_left_click(cfg!(target_os = "macos"))
        .icon_as_template(cfg!(target_os = "macos"))
        .on_menu_event(|app, event| handle_menu(app, event.id().as_ref()))
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                if !cfg!(target_os = "macos") {
                    show_main(tray.app_handle());
                }
            }
        });
    if let Some(image) = icon(false) {
        builder = builder.icon(image);
    }
    builder.build(app)?;
    Ok(())
}

pub fn update(app: &AppHandle) {
    let Some(tray) = app.tray_by_id(TRAY_ID) else { return };
    let (waiting, working) = {
        let boss = app.state::<Boss>();
        let data = boss.data();
        (data.count(AgentStatus::NeedsApproval), data.count(AgentStatus::Working))
    };
    if let Ok(menu) = build_menu(app) {
        let _ = tray.set_menu(Some(menu));
    }
    if let Some(image) = icon(waiting > 0) {
        let _ = tray.set_icon(Some(image));
        let _ = tray.set_icon_as_template(cfg!(target_os = "macos"));
    }
    let title = if waiting > 0 { waiting.to_string() } else if working > 0 { working.to_string() } else { String::new() };
    if cfg!(target_os = "macos") {
        let _ = tray.set_title(Some(title));
    }
    let _ = tray.set_tooltip(Some(summary(app)));
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.set_badge_count(if waiting > 0 { Some(waiting as i64) } else { None });
    }
}

fn summary(app: &AppHandle) -> String {
    let boss = app.state::<Boss>();
    let data = boss.data();
    trf!(
        "%d waiting · %d working · %d done",
        data.count(AgentStatus::NeedsApproval),
        data.count(AgentStatus::Working),
        data.count(AgentStatus::Finished)
    )
}

fn build_menu(app: &AppHandle) -> tauri::Result<Menu<Wry>> {
    let (sessions, open_mail) = {
        let boss = app.state::<Boss>();
        let data = boss.data();
        (data.sessions.clone(), data.open_suggestions().count())
    };
    let mut builder = MenuBuilder::new(app).item(&disabled(app, &summary(app))?);
    let sections = [
        (AgentStatus::NeedsApproval, tr("Needs you")),
        (AgentStatus::Working, tr("Working")),
        (AgentStatus::Finished, tr("Recently done")),
    ];
    let mut listed = 0;
    for (status, heading) in sections {
        let group: Vec<&AgentSession> = sessions.iter().filter(|s| s.status == status).take(LISTED_SESSIONS - listed.min(LISTED_SESSIONS)).collect();
        if group.is_empty() || listed >= LISTED_SESSIONS {
            continue;
        }
        builder = builder.separator().item(&disabled(app, &heading)?);
        for session in group {
            let label = format!("{} · {}", robot_name(session), boss_core::util::truncated(&session.title, 48));
            builder = builder.item(&MenuItemBuilder::with_id(format!("robot:{}", session.id), label).build(app)?);
            listed += 1;
        }
    }
    if sessions.is_empty() {
        builder = builder.separator().item(&disabled(app, &tr("No agent in sight."))?);
    }
    let mail = if open_mail > 0 { format!("{} ({open_mail})", tr("Mail")) } else { tr("Mail") };
    builder
        .separator()
        .item(&MenuItemBuilder::with_id("open", tr("Open the office")).build(app)?)
        .item(&MenuItemBuilder::with_id("panel:inbox", mail).build(app)?)
        .item(&MenuItemBuilder::with_id("panel:usage", tr("Usage")).build(app)?)
        .item(&PredefinedMenuItem::separator(app)?)
        .item(&MenuItemBuilder::with_id("quit", tr("Quit")).build(app)?)
        .build()
}

fn disabled(app: &AppHandle, text: &str) -> tauri::Result<MenuItem<Wry>> {
    MenuItemBuilder::new(text).enabled(false).build(app)
}

fn handle_menu(app: &AppHandle, id: &str) {
    match id {
        "quit" => app.exit(0),
        "open" => show_main(app),
        _ => {
            show_main(app);
            if let Some(panel) = id.strip_prefix("panel:") {
                let _ = app.emit("open-panel", panel.to_string());
            } else if id.starts_with("robot:") {
                let _ = app.emit("open-panel", id.to_string());
            }
        }
    }
}

pub fn show_main(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

pub fn robot_name(session: &AgentSession) -> String {
    let prefix = match session.harness {
        Harness::Claude => "CLAUDE",
        Harness::Codex => "CODEX",
        Harness::Gemini => "GEMINI",
        Harness::Copilot => "COPILOT",
        Harness::Cursor => "CURSOR",
        Harness::Pi => "PI",
        Harness::Omp => "OMP",
    };
    let hash = session.session_id.bytes().fold(2_166_136_261u32, |hash, byte| (hash ^ byte as u32).wrapping_mul(16_777_619));
    format!("{prefix}-{}", hash % 900 + 100)
}
