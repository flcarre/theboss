use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

use crate::localization::tr;
use crate::paths::Paths;
use crate::suggestions::Suggestion;
use crate::trf;
use crate::util::{last_path_component, run_with_deadline, ProcessOutcome};

pub const POLL_INTERVAL: Duration = Duration::from_millis(200);
pub const REFRESH_TIMEOUT: Duration = Duration::from_secs(60);
pub const REFINE_TIMEOUT: Duration = Duration::from_secs(90);

pub fn working_directory() -> PathBuf {
    let dir = Paths::app_data().join("rule-writer");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

pub fn claude_candidates() -> Vec<PathBuf> {
    let home = Paths::home();
    let mut candidates = vec![
        home.join(".local/bin/claude"),
        PathBuf::from("/opt/homebrew/bin/claude"),
        PathBuf::from("/usr/local/bin/claude"),
        home.join(".claude/local/claude"),
    ];
    if cfg!(windows) {
        candidates.push(home.join(".local").join("bin").join("claude.exe"));
        let roaming = std::env::var_os("APPDATA").map(PathBuf::from).unwrap_or_else(Paths::config_dir);
        candidates.push(roaming.join("npm").join("claude.cmd"));
    }
    candidates
}

pub fn is_executable_file(path: &Path) -> bool {
    let Ok(metadata) = std::fs::metadata(path) else { return false };
    if !metadata.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}

pub fn claude_executable() -> Option<PathBuf> {
    claude_candidates().into_iter().find(|path| is_executable_file(path)).or_else(|| which::which("claude").ok())
}

pub fn prompt_for(suggestion: &Suggestion) -> String {
    let quotes = suggestion
        .evidence
        .iter()
        .take(5)
        .map(|evidence| {
            let mut block = format!("- The developer wrote: \"{}\"", evidence.quote);
            if let Some(context) = &evidence.context {
                block.push_str(&format!("\n  right after the agent said: \"{context}\""));
            }
            block
        })
        .collect::<Vec<_>>()
        .join("\n");
    let file = last_path_component(&suggestion.file_path);
    format!(
        "A developer had to correct their coding agent. Here are their messages:\n\
         {quotes}\n\
         \n\
         Write ONE general rule to add to the project's {file} file so the agent never repeats this mistake.\n\
         Constraints: a single imperative sentence, 25 words at most, in the developer's language, without naming a file, ticket or date.\n\
         If no general rule emerges, answer exactly NONE.\n\
         Answer with the rule only, no quotes or bullet."
    )
}

fn claude_command(executable: &Path, prompt: &str) -> Command {
    let mut command = Command::new(executable);
    command.args(["-p", prompt, "--model", "haiku"]).current_dir(working_directory());
    command
}

pub fn refresh_claude_login(timeout: Duration) -> bool {
    let Some(executable) = claude_executable() else { return false };
    let mut command = claude_command(&executable, "Reply with just ok.");
    match run_with_deadline(&mut command, timeout, POLL_INTERVAL) {
        ProcessOutcome::Exited { code, stdout } => code == Some(0) && !looks_like_error(&stdout),
        _ => false,
    }
}

pub fn refine(suggestion: &Suggestion, timeout: Duration) -> Result<Option<String>, String> {
    let Some(executable) = claude_executable() else {
        return Err(tr("Claude Code was not found on this Mac."));
    };
    let mut command = claude_command(&executable, &prompt_for(suggestion));
    match run_with_deadline(&mut command, timeout, POLL_INTERVAL) {
        ProcessOutcome::FailedToStart(error) => Err(error.to_string()),
        ProcessOutcome::TimedOut => Err(tr("Claude did not answer in time.")),
        ProcessOutcome::Exited { code, stdout } => {
            if code != Some(0) || looks_like_error(&stdout) {
                let detail = stdout.trim().split('\n').find(|line| !line.is_empty()).unwrap_or("erreur inconnue").to_string();
                return Err(trf!("Claude Code failed: %@", detail));
            }
            Ok(clean(&stdout))
        }
    }
}

pub fn looks_like_error(text: &str) -> bool {
    let lower = text.to_lowercase();
    ["failed to authenticate", "invalid api key", "please run /login", "oauth", "api error", "credit balance"]
        .iter()
        .any(|marker| lower.contains(marker))
}

pub fn clean(text: &str) -> Option<String> {
    let first = text.trim().split('\n').find(|line| !line.is_empty()).unwrap_or("");
    let mut line = first
        .trim_matches(|c: char| "-•*«»\"' ".contains(c) || (c.is_whitespace() && c != '\n'))
        .to_string();
    if line.is_empty() || line.to_uppercase().starts_with("NONE") {
        return None;
    }
    if !line.ends_with('.') {
        line.push('.');
    }
    Some(line)
}
