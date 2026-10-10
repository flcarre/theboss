use crate::localization::tr;
use crate::models::{AgentSession, Harness};
#[cfg(not(windows))]
use crate::paths::Paths;
use crate::rule_writer::claude_executable;
use crate::trf;

pub fn resume_command(session: &AgentSession) -> String {
    let cd = if session.cwd.is_empty() { String::new() } else { format!("cd {} && ", shell_quote(&session.cwd)) };
    let id = &session.session_id;
    let command = match session.harness {
        Harness::Claude => format!("claude --resume {id}"),
        Harness::Codex => format!("codex resume {id}"),
        Harness::Gemini => format!("gemini --resume {id}"),
        Harness::Copilot => format!("copilot --resume {id}"),
        Harness::Pi => "pi --continue".to_string(),
        Harness::Omp => "omp --continue".to_string(),
        Harness::Cursor => format!("cursor-agent resume {id}"),
    };
    cd + &command
}

pub fn shell_quote(value: &str) -> String {
    if cfg!(windows) {
        format!("\"{}\"", value.replace('"', "\\\""))
    } else {
        posix_quote(value)
    }
}

pub fn posix_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

pub fn fallback_app_names(harness: Harness) -> &'static [&'static str] {
    match harness {
        Harness::Codex => &["Codex"],
        Harness::Cursor => &["Cursor"],
        Harness::Copilot => &["Visual Studio Code", "Code"],
        _ => &[],
    }
}

pub fn app_bundle(executable: &str) -> Option<String> {
    if !executable.contains(".app/Contents/MacOS/") {
        return None;
    }
    let end = executable.find(".app/")? + ".app".len();
    Some(executable[..end].to_string())
}

#[cfg(target_os = "macos")]
pub fn focus(session: &AgentSession) -> bool {
    use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};

    let mut system = System::new();
    system.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing().with_exe(UpdateKind::OnlyIfNotSet),
    );
    let bundle_of = |pid: Pid| -> Option<String> { app_bundle(&system.process(pid)?.exe()?.to_string_lossy()) };

    if let Some(pid) = session.pid {
        let mut current = Pid::from_u32(pid);
        for _ in 0..12 {
            if let Some(bundle) = bundle_of(current) {
                return activate(&bundle);
            }
            match system.process(current).and_then(|process| process.parent()) {
                Some(parent) if parent.as_u32() > 1 && parent != current => current = parent,
                _ => break,
            }
        }
    }
    let names = fallback_app_names(session.harness);
    if names.is_empty() {
        return false;
    }
    let mut bundles: Vec<String> = system.processes().keys().filter_map(|pid| bundle_of(*pid)).collect();
    bundles.sort();
    bundles.dedup();
    let found = bundles.into_iter().find(|bundle| {
        let name = crate::util::last_path_component(bundle).trim_end_matches(".app").to_lowercase();
        names.iter().any(|candidate| name.contains(&candidate.to_lowercase()))
    });
    found.is_some_and(|bundle| activate(&bundle))
}

#[cfg(target_os = "macos")]
fn activate(bundle: &str) -> bool {
    std::process::Command::new("/usr/bin/open").args(["-a", bundle]).status().is_ok_and(|status| status.success())
}

#[cfg(not(target_os = "macos"))]
pub fn focus(session: &AgentSession) -> bool {
    let _ = session;
    false
}

fn claude_program() -> String {
    claude_executable().map(|path| path.to_string_lossy().into_owned()).unwrap_or_else(|| "claude".to_string())
}

fn close_hint() -> String {
    tr("You can close this window and go back to The Boss.")
}

fn terminal_error(detail: impl std::fmt::Display) -> String {
    trf!("Could not open Terminal: %@", detail.to_string())
}

#[cfg(target_os = "macos")]
pub fn open_claude_login() -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;

    let script = Paths::app_data().join("claude-login.command");
    let body = format!("#!/bin/sh\n{} auth login\necho\necho \"{}\"\n", shell_quote(&claude_program()), close_hint());
    std::fs::write(&script, body).map_err(terminal_error)?;
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).map_err(terminal_error)?;
    let status = std::process::Command::new("/usr/bin/open").arg(&script).status().map_err(terminal_error)?;
    if status.success() {
        Ok(())
    } else {
        Err(terminal_error(status))
    }
}

#[cfg(windows)]
pub fn open_claude_login() -> Result<(), String> {
    use std::os::windows::process::CommandExt;

    let mut command = std::process::Command::new("cmd");
    command.raw_arg(format!("/c start \"The Boss\" cmd /k \"\"{}\" auth login\"", claude_program()));
    crate::util::hide_console_window(&mut command);
    command.spawn().map(|_| ()).map_err(terminal_error)
}

#[cfg(all(not(target_os = "macos"), not(windows)))]
pub fn open_claude_login() -> Result<(), String> {
    let script = linux_login_script(&claude_program());
    for (terminal, args) in linux_terminal_commands(&script) {
        if which::which(terminal).is_err() {
            continue;
        }
        if std::process::Command::new(terminal)
            .args(&args)
            .current_dir(Paths::home())
            .stdin(std::process::Stdio::null())
            .spawn()
            .is_ok()
        {
            return Ok(());
        }
    }
    Err(terminal_error("no terminal emulator found"))
}

pub fn linux_login_script(claude: &str) -> String {
    format!("{} auth login; echo; echo {}; read _", posix_quote(claude), posix_quote(&close_hint()))
}

pub fn linux_terminal_commands(script: &str) -> Vec<(&'static str, Vec<String>)> {
    let shell = |prefix: &[&str]| -> Vec<String> {
        prefix.iter().map(|part| part.to_string()).chain(["sh".to_string(), "-c".to_string(), script.to_string()]).collect()
    };
    vec![
        ("x-terminal-emulator", shell(&["-e"])),
        ("gnome-terminal", shell(&["--"])),
        ("konsole", shell(&["-e"])),
        ("xfce4-terminal", vec!["-e".to_string(), format!("sh -c {}", posix_quote(script))]),
        ("kitty", shell(&[])),
        ("alacritty", shell(&["-e"])),
        ("xterm", shell(&["-e"])),
    ]
}
