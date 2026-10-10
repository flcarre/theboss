use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};

use boss_core::claude::ClaudeSource;
use boss_core::codex::CodexSource;
use boss_core::copilot::CopilotSource;
use boss_core::cursor::CursorSource;
use boss_core::gemini::GeminiSource;
use boss_core::jsonl::{captures, contains_bytes, JsonlTail};
use boss_core::monitor::AgentMonitor;
use boss_core::transcript::ContentText;
use boss_core::{AgentStatus, Harness, MessageRole, Paths};
use chrono::{Duration, SecondsFormat, Utc};
use serde_json::{json, Value};
use tempfile::TempDir;

static LOCK: Mutex<()> = Mutex::new(());

fn serialized() -> MutexGuard<'static, ()> {
    LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn make_home() -> TempDir {
    let home = tempfile::tempdir().unwrap();
    Paths::set_home(home.path().to_path_buf());
    home
}

fn write(text: &str, path: &Path) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).unwrap();
}

fn append(text: &str, path: &Path) {
    let mut file = OpenOptions::new().append(true).open(path).unwrap();
    file.write_all(text.as_bytes()).unwrap();
}

fn jsonl(lines: &[Value]) -> String {
    lines.iter().map(Value::to_string).collect::<Vec<_>>().join("\n") + "\n"
}

fn iso(offset_secs: i64) -> String {
    (Utc::now() + Duration::seconds(offset_secs)).to_rfc3339_opts(SecondsFormat::Secs, true)
}

fn path_str(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

#[test]
fn parses_claude_transcript_with_usage_dedupe_and_pending_tool() {
    let _guard = serialized();
    let home = make_home();
    let project = home.path().join(".claude/projects/-repo");
    let file = project.join("abc.jsonl");
    let now = iso(0);
    let lines = [
        json!({"type": "custom-title", "customTitle": "Fix login", "sessionId": "abc"}),
        json!({"type": "user", "sessionId": "abc", "cwd": "/repo", "timestamp": now,
               "message": {"role": "user", "content": "Non, je t'ai dit de toujours écrire les tests d'abord."}}),
        json!({"type": "assistant", "timestamp": now, "message": {"id": "m1", "model": "claude-x",
               "content": [{"type": "text", "text": "D'accord."}], "usage": {"input_tokens": 10, "output_tokens": 5}}}),
        json!({"type": "assistant", "timestamp": now, "message": {"id": "m1", "model": "claude-x",
               "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "rm -rf build"}}],
               "usage": {"input_tokens": 10, "output_tokens": 20}}}),
    ];
    write(&jsonl(&lines), &file);
    let mut source = ClaudeSource::default();
    let state = source.parse(&file);
    assert_eq!(state.display_title(), "Fix login");
    assert_eq!(state.tokens.total(), 30);
    assert_eq!(state.prompts.len(), 1);
    assert_eq!(state.pending_description().as_deref(), Some("Bash · rm -rf build"));
    assert_eq!(state.model.as_deref(), Some("claude-x"));

    let more = json!({"type": "user", "timestamp": now, "message": {"role": "user",
                      "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}});
    append(&format!("{more}\n"), &file);
    assert!(source.parse(&file).pending_tools.is_empty());

    let sessions = source.sessions();
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0].cwd, "/repo");
}

#[test]
fn maps_live_claude_statuses() {
    assert_eq!(ClaudeSource::map(Some("busy")), Some(AgentStatus::Working));
    assert_eq!(ClaudeSource::map(Some("waiting")), Some(AgentStatus::NeedsApproval));
    assert_eq!(ClaudeSource::map(Some("idle")), Some(AgentStatus::Finished));
    assert_eq!(ClaudeSource::map(None), None);
}

#[test]
fn parses_codex_rollout_status_and_rate_limits() {
    let _guard = serialized();
    let home = make_home();
    let file = home.path().join(".codex/sessions/2026/10/10/rollout-x.jsonl");
    let now = iso(0);
    let reset = (Utc::now() + Duration::seconds(3600)).timestamp();
    let lines = [
        json!({"type": "session_meta", "timestamp": now, "payload": {"id": "cx1", "cwd": "/repo", "timestamp": now}}),
        json!({"type": "event_msg", "timestamp": now, "payload": {"type": "task_started"}}),
        json!({"type": "response_item", "timestamp": now, "payload": {"type": "message", "role": "user",
               "content": [{"type": "input_text", "text": "Refactor the parser"}]}}),
        json!({"type": "event_msg", "timestamp": now, "payload": {"type": "token_count",
               "info": {"total_token_usage": {"input_tokens": 100, "cached_input_tokens": 40, "output_tokens": 10}},
               "rate_limits": {"primary": {"used_percent": 42.0, "window_minutes": 300, "resets_at": reset},
                               "secondary": {"used_percent": 7.0, "window_minutes": 10080, "resets_at": reset},
                               "plan_type": "plus"}}}),
        json!({"type": "response_item", "timestamp": now, "payload": {"type": "function_call", "call_id": "c1",
               "name": "request_user_input", "arguments": "{}"}}),
    ];
    write(&jsonl(&lines), &file);
    let mut source = CodexSource::default();
    let sessions = source.sessions();
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0].status, AgentStatus::NeedsApproval);
    assert_eq!(sessions[0].tokens.total(), 110);
    let limits = source.latest_rate_limits().expect("rate limits");
    assert_eq!(limits.plan.as_deref(), Some("plus"));
    assert_eq!(limits.windows.iter().map(|w| w.label.as_str()).collect::<Vec<_>>(), ["5 h", "Week"]);
    assert_eq!(limits.windows[0].used_percent, 42.0);
    assert!(limits.windows[0].resets_at.is_some());
}

#[test]
fn labels_codex_rate_windows() {
    assert_eq!(CodexSource::window_label(300), "5 h");
    assert_eq!(CodexSource::window_label(2 * 24 * 60), "2 days");
    assert_eq!(CodexSource::window_label(10080), "Week");
}

#[test]
fn reads_pi_omp_and_cursor_sessions() {
    let _guard = serialized();
    let home = make_home();
    let now = iso(0);
    let lines = [
        json!({"type": "session", "version": 3, "id": "pi-1", "timestamp": now, "cwd": "/work/api"}),
        json!({"type": "message", "id": "a0", "parentId": null, "timestamp": now,
               "message": {"role": "system", "content": "", "sections": {"preamble": "You are an expert coding assistant"}}}),
        json!({"type": "message", "id": "a1", "parentId": "a0", "timestamp": now,
               "message": {"role": "user", "content": "Ajoute la pagination", "timestamp": 1}}),
        json!({"type": "message", "id": "a2", "parentId": "a1", "timestamp": now, "message": {"role": "assistant", "model": "gpt-x",
               "api": "openai-responses", "provider": "openai", "stopReason": "toolUse",
               "content": [{"type": "toolCall", "id": "call1", "name": "bash", "arguments": {"command": "npm test"}}],
               "usage": {"input": 100, "output": 20, "cacheRead": 5, "cacheWrite": 0, "totalTokens": 125}}}),
        json!({"type": "usage", "id": "a3", "parentId": "a2", "timestamp": now, "kind": "cache_warm", "provider": "openai",
               "model": "gpt-x", "usage": {"input": 0, "output": 0, "cacheRead": 50, "cacheWrite": 0}}),
    ];
    let text = jsonl(&lines);
    write(&text, &home.path().join(".pi/agent/sessions/--work-api--/s.jsonl"));
    write(&text, &home.path().join(".omp/agent/sessions/--work-api--/s.jsonl"));
    write("", &home.path().join(".cursor/chats/abc/chat1/store.db"));

    let sessions = AgentMonitor::new(true).sessions();
    let pi = sessions.iter().find(|s| s.harness == Harness::Pi).expect("pi session");
    assert_eq!(pi.cwd, "/work/api");
    assert_eq!(pi.title, "Ajoute la pagination");
    assert_eq!(pi.tokens.total(), 175);
    assert_eq!(pi.model.as_deref(), Some("gpt-x"));
    assert_eq!(pi.status, AgentStatus::Working);
    assert!(sessions.iter().any(|s| s.harness == Harness::Omp && s.session_id == "pi-1"));
    assert!(sessions.iter().any(|s| s.harness == Harness::Cursor && s.status == AgentStatus::Working));
}

#[test]
fn cursor_chats_get_their_name_and_project() {
    let _guard = serialized();
    let home = make_home();
    let project = home.path().join("code").join("my-shop");
    std::fs::create_dir_all(&project).unwrap();
    let project_path = path_str(&project);
    let slug = project_path.trim_start_matches('/').replace('/', "-");
    std::fs::create_dir_all(home.path().join(".cursor/projects").join(&slug)).unwrap();
    let named: PathBuf = home
        .path()
        .join(".cursor/chats")
        .join(CursorSource::workspace_hash(&project_path))
        .join("chat-named/store.db");
    std::fs::create_dir_all(named.parent().unwrap()).unwrap();
    let meta: String = br#"{"agentId":"chat-named","name":"Fix the cart total"}"#.iter().map(|b| format!("{b:02x}")).collect();
    let connection = rusqlite::Connection::open(&named).unwrap();
    connection
        .execute_batch(&format!("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT); INSERT INTO meta VALUES ('0', '{meta}');"))
        .unwrap();
    drop(connection);
    write("", &home.path().join(".cursor/chats/unknown/chat-blank/store.db"));

    if cfg!(unix) {
        assert_eq!(CursorSource::directory_from_slug(&slug).as_deref(), Some(project_path.as_str()));
    }
    let sessions: Vec<_> = AgentMonitor::new(true).sessions().into_iter().filter(|s| s.harness == Harness::Cursor).collect();
    let chat = sessions.iter().find(|s| s.session_id == "chat-named").expect("named chat");
    assert_eq!(chat.title, "Fix the cart total");
    if cfg!(unix) {
        assert_eq!(chat.cwd, project_path);
    }
    let blank = sessions.iter().find(|s| s.session_id == "chat-blank").expect("blank chat");
    assert_eq!(blank.title, "Cursor chat chat-b");
    assert!(blank.cwd.is_empty());
}

#[test]
fn reads_cursor_meta_names() {
    assert_eq!(CursorSource::name_from_meta(br#"{"title":" Plan "}"#).as_deref(), Some("Plan"));
    assert_eq!(CursorSource::name_from_meta(br#"{"name":"New Chat"}"#), None);
    assert_eq!(CursorSource::hex_decoded("7b7d"), Some(b"{}".to_vec()));
    assert_eq!(CursorSource::hex_decoded("7b7"), None);
}

#[test]
fn reads_gemini_jsonl_sessions() {
    let _guard = serialized();
    let home = make_home();
    let project = home.path().join(".gemini/tmp/shop-api");
    write("/work/shop-api\n", &project.join(".project_root"));
    let now = iso(0);
    let old = iso(-3600);
    let lines = [
        json!({"sessionId": "gem-1", "projectHash": "abc", "startTime": old, "lastUpdated": old, "kind": "main"}),
        json!({"id": "u1", "timestamp": old, "type": "user", "content": [{"text": "Ajoute un cache Redis"}]}),
        json!({"id": "g1", "timestamp": old, "type": "gemini", "content": "", "model": "gemini-3-pro"}),
        json!({"id": "g1", "timestamp": old, "type": "gemini", "content": "", "model": "gemini-3-pro",
               "toolCalls": [{"id": "t1", "name": "run_shell_command", "args": {}, "status": "success", "timestamp": old}],
               "tokens": {"input": 100, "output": 10, "cached": 40, "total": 110}}),
        json!({"id": "u2", "timestamp": old, "type": "user", "content": [{"functionResponse": {"name": "run_shell_command"}}]}),
        json!({"id": "g2", "timestamp": now, "type": "gemini", "content": "C'est fait.", "model": "gemini-3-pro",
               "tokens": {"input": 200, "output": 20, "cached": 0, "total": 220}}),
        json!({"$set": {"lastUpdated": now, "summary": "Cache Redis"}}),
        json!({"id": "u3", "timestamp": now, "type": "user", "content": [{"text": "Non, jamais de TTL infini"}]}),
        json!({"$rewindTo": "u3"}),
    ];
    write(&jsonl(&lines), &project.join("chats/session-2026-10-10T08-00-gem1abcd.jsonl"));
    let mut source = GeminiSource::default();
    let sessions = source.sessions();
    let session = sessions.first().expect("gemini session");
    assert_eq!(session.harness, Harness::Gemini);
    assert_eq!(session.cwd, "/work/shop-api");
    assert_eq!(session.title, "Cache Redis");
    assert_eq!(session.prompt_count, 1);
    assert_eq!(session.last_reply.as_deref(), Some("C'est fait."));
    assert_eq!(session.tokens.total(), 330);
    assert_eq!(session.model.as_deref(), Some("gemini-3-pro"));
    let path = PathBuf::from(session.transcript_path.clone().expect("transcript path"));
    let roles: Vec<MessageRole> = source.messages(&path).into_iter().map(|m| m.role).collect();
    assert_eq!(roles, [MessageRole::User, MessageRole::Assistant]);
}

#[test]
fn reads_copilot_events_and_pending_permissions() {
    let _guard = serialized();
    let home = make_home();
    let dir = home.path().join(".copilot/session-state/cop-1");
    write("id: cop-1\ncwd: /work/web\nsummary: \"Fix the login form\"\n", &dir.join("workspace.yaml"));
    let pid = std::process::id();
    write(&pid.to_string(), &dir.join(format!("inuse.{pid}.lock")));
    let now = iso(0);
    let lines = [
        json!({"id": "e1", "timestamp": now, "type": "session.start",
               "data": {"sessionId": "cop-1", "selectedModel": "gpt-5", "context": {"cwd": "/work/web"}}}),
        json!({"id": "e2", "timestamp": now, "type": "user.message", "data": {"content": "Corrige le formulaire de login"}}),
        json!({"id": "e3", "timestamp": now, "type": "assistant.turn_start", "data": {"turnId": "1"}}),
        json!({"id": "e4", "timestamp": now, "type": "assistant.message", "data": {"messageId": "m1", "content": "Je regarde.",
               "toolRequests": [{"toolCallId": "c1", "name": "bash"}]}}),
        json!({"id": "e5", "timestamp": now, "type": "permission.requested", "data": {"requestId": "p1",
               "permissionRequest": {"kind": "shell", "fullCommandText": "npm test", "intention": "Run tests"}}}),
    ];
    let events = dir.join("events.jsonl");
    write(&jsonl(&lines), &events);
    let mut source = CopilotSource::default();
    let session = source.sessions().into_iter().next().expect("copilot session");
    assert_eq!(session.harness, Harness::Copilot);
    assert_eq!(session.status, AgentStatus::NeedsApproval);
    assert_eq!(session.pending_action.as_deref(), Some("shell · npm test"));
    assert_eq!(session.title, "Fix the login form");
    assert_eq!(session.cwd, "/work/web");
    assert_eq!(session.model.as_deref(), Some("gpt-5"));
    assert_eq!(session.pid, Some(pid));

    let more = [
        json!({"id": "e6", "timestamp": now, "type": "permission.completed", "data": {"requestId": "p1", "result": {"kind": "approved"}}}),
        json!({"id": "e7", "timestamp": now, "type": "assistant.message", "data": {"messageId": "m2", "content": "Tests verts."}}),
        json!({"id": "e8", "timestamp": now, "type": "assistant.turn_end", "data": {"turnId": "1"}}),
        json!({"id": "e9", "timestamp": now, "type": "session.shutdown", "data": {"shutdownType": "routine",
               "modelMetrics": {"gpt-5": {"usage": {"inputTokens": 1000, "outputTokens": 50, "cacheReadTokens": 400, "cacheWriteTokens": 0}}}}}),
    ];
    append(&jsonl(&more), &events);
    let session = source.sessions().into_iter().next().expect("copilot session");
    assert_eq!(session.status, AgentStatus::Finished);
    assert_eq!(session.last_reply.as_deref(), Some("Tests verts."));
    assert_eq!(session.tokens.total(), 1050);
}

#[test]
fn monitor_aggregates_prompts_tokens_and_installed_harnesses() {
    let _guard = serialized();
    let home = make_home();
    let now = iso(0);
    let lines = [
        json!({"type": "session", "id": "pi-2", "timestamp": now, "cwd": "/work/api"}),
        json!({"type": "message", "timestamp": now, "message": {"role": "user", "content": "Ajoute un test"}}),
        json!({"type": "message", "timestamp": now, "message": {"role": "assistant", "content": [{"type": "text", "text": "Fait."}],
               "usage": {"input": 10, "output": 5}}}),
    ];
    let file = home.path().join(".pi/agent/sessions/x/s.jsonl");
    write(&jsonl(&lines), &file);
    let monitor = AgentMonitor::new(true);
    assert_eq!(monitor.installed_harnesses(), [Harness::Pi]);
    let prompts = monitor.prompts(3600.0);
    assert_eq!(prompts.len(), 1);
    assert_eq!(prompts[0].text, "Ajoute un test");
    assert_eq!(prompts[0].session_id, "pi-2");
    let daily = monitor.daily_tokens(3600.0);
    assert_eq!(daily.len(), 1);
    assert_eq!(daily[0].harness, Harness::Pi);
    assert_eq!(daily[0].tokens.total(), 15);
    let session = monitor.sessions().into_iter().find(|s| s.harness == Harness::Pi).expect("pi session");
    let messages = monitor.messages(&session);
    assert_eq!(messages.iter().map(|m| m.text.as_str()).collect::<Vec<_>>(), ["Ajoute un test", "Fait."]);
    assert!(monitor.codex_rate_limits().is_none());
}

#[test]
fn jsonl_tail_reads_only_complete_lines_and_resets_on_truncation() {
    let _guard = serialized();
    let home = make_home();
    let file = home.path().join("t.jsonl");
    write("{\"a\":1}\n{\"b\":", &file);
    let mut tail = JsonlTail::default();
    let (objects, reset) = tail.read_new_objects(&file);
    assert_eq!(objects.len(), 1);
    assert!(!reset);
    append("2}\n", &file);
    let (objects, _) = tail.read_new_objects(&file);
    assert_eq!(objects, [json!({"b": 2})]);
    assert!(tail.read_new_lines(&file).0.is_empty());
    write("{\"c\":3}\n", &file);
    let (objects, reset) = tail.read_new_objects(&file);
    assert!(reset);
    assert_eq!(objects, [json!({"c": 3})]);
}

#[test]
fn byte_helpers_find_markers_and_capture_values() {
    let line = br#"{"tool_use_id":"t1","x":{"tool_use_id":"t2"},"timestamp":"2026"}"#;
    assert!(contains_bytes(line, "\"tool_use_id\""));
    assert!(!contains_bytes(line, "\"assistant\""));
    assert_eq!(captures(line, "\"tool_use_id\":\"", 64), ["t1", "t2"]);
    assert_eq!(captures(line, "\"tool_use_id\":\"", 1), ["t1"]);
    assert_eq!(captures(line, "\"timestamp\":\"", 1), ["2026"]);
}

#[test]
fn cleans_user_text_noise_and_commands() {
    assert_eq!(ContentText::clean_user_text("<command-name>review</command-name><command-args> 12 </command-args>").as_deref(), Some("/review 12"));
    assert_eq!(ContentText::clean_user_text("<system-reminder>x</system-reminder>"), None);
    assert_eq!(ContentText::clean_user_text("Fix it <system-reminder>noise</system-reminder> now").as_deref(), Some("Fix it  now"));
    assert_eq!(ContentText::clean_user_text("   "), None);
}

#[test]
fn agent_monitor_is_shareable_across_threads() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<AgentMonitor>();
}
