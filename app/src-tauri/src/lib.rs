mod commands;
mod state;
mod tray;
mod workers;

use tauri::{RunEvent, WindowEvent};

pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| tray::show_main(app)))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_opener::init())
        .manage(state::Boss::new())
        .invoke_handler(tauri::generate_handler![
            commands::snapshot,
            commands::messages,
            commands::set_suggestion_status,
            commands::refine_suggestion,
            commands::domain_projects,
            commands::domain_model,
            commands::save_intent,
            commands::export_domain,
            commands::save_settings,
            commands::record_whip,
            commands::focus_session,
            commands::open_claude_login,
            commands::repair_claude_usage,
            commands::refresh_usage,
            commands::rule_content,
        ])
        .setup(|app| {
            tray::install(app.handle())?;
            workers::start(app.handle());
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                if window.label() == "main" {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .build(tauri::generate_context!())
        .expect("error while building The Boss");

    app.run(|handle, event| match event {
        #[cfg(target_os = "macos")]
        RunEvent::Reopen { .. } => tray::show_main(handle),
        _ => {
            let _ = handle;
        }
    });
}
