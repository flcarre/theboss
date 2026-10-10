use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

use base64::Engine;
use boss_core::analytics::{self, Trend};
use boss_core::corrections;
use boss_core::cursor_auth;
use boss_core::diff::{self, DiffLineKind};
use boss_core::domain;
use boss_core::launcher;
use boss_core::localization::{set_language, AppLanguage};
use boss_core::models::{AgentSession, AgentStatus, DailyTokens, Harness, TokenUsage, UserPrompt};
use boss_core::monitor::AgentMonitor;
use boss_core::paths::Paths;
use boss_core::rule_writer;
use boss_core::rules::{self, RuleKind};
use boss_core::store::Store;
use boss_core::suggestions::{Evidence, Suggestion, SuggestionEngine, SuggestionKind, SuggestionOperation, SuggestionStatus};
use boss_core::usage::{
    self, ClaudeUsageClient, KeychainResult, ProviderUsage, UsageEndpoints, UsageOptions, UsageService, UsageState,
};
use boss_core::util::{day_key, now};
use tempfile::TempDir;

static LOCK: Mutex<()> = Mutex::new(());

struct Home {
    dir: TempDir,
    _guard: MutexGuard<'static, ()>,
}

impl Home {
    fn join(&self, relative: &str) -> PathBuf {
        self.dir.path().join(relative)
    }
}

fn make_home() -> Home {
    let guard = LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let dir = tempfile::tempdir().unwrap();
    Paths::set_home(dir.path().to_path_buf());
    Home { dir, _guard: guard }
}

fn write(text: &str, path: &Path) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).unwrap();
}

fn path_str(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn prompt(text: &str, cwd: &str) -> UserPrompt {
    UserPrompt {
        harness: Harness::Claude,
        session_id: "s".into(),
        cwd: cwd.into(),
        text: text.into(),
        timestamp: None,
        previous_assistant: None,
    }
}

fn git_project(home: &Home, name: &str) -> PathBuf {
    let project = home.join(name);
    std::fs::create_dir_all(project.join(".git")).unwrap();
    project
}

struct StubState {
    status: u16,
    body: String,
    last_authorization: Option<String>,
    hits: usize,
}

struct Stub {
    url: String,
    state: Arc<Mutex<StubState>>,
}

impl Stub {
    fn start(status: u16, body: &str) -> Stub {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/api/oauth/usage", listener.local_addr().unwrap());
        let state = Arc::new(Mutex::new(StubState { status, body: body.into(), last_authorization: None, hits: 0 }));
        let shared = state.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                let mut request = Vec::new();
                let mut buffer = [0u8; 4096];
                while !request.windows(4).any(|window| window == b"\r\n\r\n") {
                    match stream.read(&mut buffer) {
                        Ok(0) | Err(_) => break,
                        Ok(read) => request.extend_from_slice(&buffer[..read]),
                    }
                }
                let text = String::from_utf8_lossy(&request).into_owned();
                let mut state = shared.lock().unwrap();
                state.hits += 1;
                state.last_authorization = text
                    .lines()
                    .find(|line| line.to_ascii_lowercase().starts_with("authorization:"))
                    .map(|line| line["authorization:".len()..].trim().to_string());
                let response = format!(
                    "HTTP/1.1 {} Stub\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    state.status,
                    state.body.len(),
                    state.body
                );
                let _ = stream.write_all(response.as_bytes());
            }
        });
        Stub { url, state }
    }

    fn set(&self, status: u16, body: &str) {
        let mut state = self.state.lock().unwrap();
        state.status = status;
        state.body = body.into();
    }

    fn last_authorization(&self) -> Option<String> {
        self.state.lock().unwrap().last_authorization.clone()
    }

    fn hits(&self) -> usize {
        self.state.lock().unwrap().hits
    }
}

const CREDENTIALS: &str = r#"{"claudeAiOauth":{"accessToken":"tok-123","expiresAt":4102444800000,"subscriptionType":"team"}}"#;
const CLAUDE_USAGE: &str = r#"{"five_hour":{"utilization":37,"resets_at":"2099-10-10T12:00:00Z"},"seven_day":{"utilization":12,"resets_at":"2099-10-14T00:00:00Z"}}"#;

fn found(credentials: &str) -> usage::CredentialReader {
    let data = credentials.as_bytes().to_vec();
    Arc::new(move || KeychainResult::Found(data.clone()))
}

fn jwt(payload: &str) -> String {
    let encoded = base64::engine::general_purpose::STANDARD.encode(payload).replace('=', "");
    format!("h.{encoded}.s")
}

#[test]
fn detects_corrections_and_extracts_rules() {
    let _home = make_home();
    let correction = corrections::detect(&prompt("Non, n'utilise jamais de force push sur main.", "/p"));
    assert!(correction.is_some());
    assert_eq!(correction.unwrap().rule.as_deref(), Some("N'utilise jamais de force push sur main."));
    assert!(corrections::detect(&prompt("Ajoute un bouton d'export CSV sur la page des flows", "/p")).is_none());
}

#[test]
fn ignores_specific_one_off_instructions() {
    let _home = make_home();
    let correction = corrections::detect(&prompt("non, toujours relire https://example.com/issues/12 avant", "/p"));
    assert!(correction.and_then(|correction| correction.rule).is_none());
}

#[test]
fn appends_learned_rules_under_one_section() {
    let _home = make_home();
    let first = SuggestionEngine::appending("Toujours lancer les tests.", "# Projet\n\nIntro.\n");
    assert_eq!(first, "# Projet\n\nIntro.\n\n## Learned rules\n\n- Toujours lancer les tests.\n");
    let second = SuggestionEngine::appending("Jamais de console.log.", &first);
    assert_eq!(second.split(SuggestionEngine::learned_section().as_str()).count(), 2);
    assert!(second.ends_with("- Toujours lancer les tests.\n- Jamais de console.log.\n"));
}

#[test]
fn unified_diff_shows_added_and_removed_lines() {
    let _home = make_home();
    let lines = diff::lines("a\nb\nc", "a\nB\nc\nd", "f.md", 3);
    let of_kind = |kind: DiffLineKind| lines.iter().filter(|line| line.kind == kind).map(|line| line.text.clone()).collect::<Vec<_>>();
    assert_eq!(of_kind(DiffLineKind::Added), vec!["+B", "+d"]);
    assert_eq!(of_kind(DiffLineKind::Removed), vec!["-b"]);
    assert_eq!(lines.first().map(|line| line.text.as_str()), Some("--- a/f.md"));
    assert!(diff::lines("same", "same", "f", 3).is_empty());
    assert!(diff::text("", "new", "f").starts_with("--- /dev/null\n+++ b/f\n@@ -0,0 +1,1 @@\n+new"));
}

#[test]
fn inventories_hooks_skills_and_rules() {
    let home = make_home();
    write("# Global rules\n", &home.join(".claude/CLAUDE.md"));
    write(
        r#"{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"lint.sh"}]}]}}"#,
        &home.join(".claude/settings.json"),
    );
    write("---\nname: deploy\ndescription: Ship to prod\n---\n# Deploy\n", &home.join(".claude/skills/deploy/SKILL.md"));
    let project = git_project(&home, "repo");
    write("Use pnpm.\n", &project.join("AGENTS.md"));
    let items = rules::scan(&[path_str(&project)]);
    assert!(items.iter().any(|item| item.kind == RuleKind::Hook && item.name == "PreToolUse · Bash" && item.summary == "lint.sh"));
    assert!(items.iter().any(|item| item.kind == RuleKind::Skill && item.name == "deploy" && item.summary == "Ship to prod"));
    assert!(items.iter().any(|item| item.kind == RuleKind::Instructions && item.scope == "repo" && item.name == "AGENTS.md"));
    let skill = items.iter().find(|item| item.kind == RuleKind::Skill).unwrap();
    assert_eq!(skill.id, format!("{}#deploy", skill.path));
    assert!(skill.path.ends_with("SKILL.md"));
}

#[test]
fn finds_project_roots() {
    let home = make_home();
    let project = git_project(&home, "repo");
    assert_eq!(rules::project_root(&path_str(&project.join("src/deep"))), path_str(&project));
    assert_eq!(rules::project_root("/x/app/.claude/worktrees/feature-1/src"), "/x/app");
    assert_eq!(rules::project_root("C:\\x\\app\\.claude\\worktrees\\feature-1"), "C:\\x\\app");
    assert_eq!(rules::project_root(""), "");
    assert_eq!(rules::summary("---\nname: x\n---\n\n# Title here\nbody"), "Title here");
    assert_eq!(rules::summary("{\n\"a\": 1\n}\n"), "\"a\": 1");
}

#[test]
fn proposes_setup_fixes() {
    let home = make_home();
    let project = git_project(&home, "repo");
    write("Use pnpm.\n", &project.join("AGENTS.md"));
    write("@docs/missing.md\n# Me\n", &home.join(".claude/CLAUDE.md"));
    let session = AgentSession::new(Harness::Claude, "s", "t", path_str(&project), AgentStatus::Finished, now());
    let fixes = SuggestionEngine::new().setup_fixes(&[session]);
    let import_fix = fixes.iter().find(|fix| fix.title == "Make Claude Code read AGENTS.md").unwrap();
    assert_eq!(import_fix.proposed_content(), "@AGENTS.md\n");
    let broken = fixes.iter().find(|fix| fix.title == "Remove a broken import").unwrap();
    assert_eq!(broken.proposed_content(), "# Me\n");
    assert!(broken.display_path().starts_with('~') && broken.display_path().ends_with("CLAUDE.md"));
    broken.apply().unwrap();
    assert_eq!(std::fs::read_to_string(home.join(".claude/CLAUDE.md")).unwrap(), "# Me\n");
}

#[test]
fn proposes_frontmatter_for_undescribed_skills() {
    let home = make_home();
    write("# Release helper\nSteps.\n", &home.join(".claude/skills/release/SKILL.md"));
    let fixes = SuggestionEngine::new().setup_fixes(&[]);
    let fix = fixes.iter().find(|fix| fix.title == "Describe the release skill").unwrap();
    assert_eq!(
        fix.operation,
        SuggestionOperation::AddFrontmatter { name: "release".into(), description: "Release helper".into() }
    );
    assert!(fix.proposed_content().starts_with("---\nname: release\ndescription: Release helper\n---\n\n# Release helper"));
}

#[test]
fn learned_rule_suggestions_skip_rules_already_written() {
    let home = make_home();
    let project = git_project(&home, "repo");
    let cwd = path_str(&project);
    let prompts = vec![
        UserPrompt {
            timestamp: Some(now()),
            previous_assistant: Some("npm install".into()),
            ..prompt("Non, toujours utiliser pnpm et jamais npm.", &cwd)
        },
        UserPrompt { timestamp: Some(now()), ..prompt("je t'ai dit: toujours utiliser pnpm, jamais npm", &cwd) },
    ];
    let engine = SuggestionEngine::new();
    let suggestions = engine.learned_rules(&engine.corrections(&prompts));
    assert_eq!(suggestions.len(), 1);
    assert_eq!(suggestions[0].evidence.len(), 2);
    assert_eq!(suggestions[0].file_path, path_str(&project.join("CLAUDE.md")));
    assert_eq!(suggestions[0].kind, SuggestionKind::LearnedRule);
    assert_eq!(suggestions[0].evidence[0].context.as_deref(), Some("npm install"));

    write("- Toujours utiliser pnpm et jamais npm.\n", &project.join("CLAUDE.md"));
    assert!(engine.learned_rules(&engine.corrections(&prompts)).is_empty());
}

#[test]
fn refining_a_suggestion_rewrites_its_rule() {
    let home = make_home();
    let mut suggestion = sample_suggestion(&home, SuggestionStatus::New);
    suggestion.refine("Toujours utiliser pnpm.");
    assert_eq!(suggestion.title, "Toujours utiliser pnpm.");
    assert_eq!(suggestion.refined_rule.as_deref(), Some("Toujours utiliser pnpm."));
    assert_eq!(suggestion.operation, SuggestionOperation::AppendRule { rule: "Toujours utiliser pnpm.".into() });
    assert!(suggestion.diff().iter().any(|line| line.text == "+- Toujours utiliser pnpm."));
    assert_eq!(SuggestionEngine::stable_id(&["a", "b"]), SuggestionEngine::stable_id(&["a", "b"]));
    assert_eq!(SuggestionEngine::stable_id(&[""]), "14650fb0739d0383");
}

fn sample_suggestion(home: &Home, status: SuggestionStatus) -> Suggestion {
    Suggestion {
        id: "x".into(),
        kind: SuggestionKind::LearnedRule,
        title: "Rule".into(),
        rationale: "Why".into(),
        project: "p".into(),
        file_path: path_str(&home.join("CLAUDE.md")),
        operation: SuggestionOperation::AppendRule { rule: "Rule.".into() },
        evidence: vec![Evidence {
            quote: "Non, jamais ça.".into(),
            context: Some("ok".into()),
            harness: Harness::Claude,
            session_id: "s".into(),
            date: Some(now()),
        }],
        status,
        created_at: now(),
        refined_rule: None,
    }
}

#[test]
fn store_keeps_suggestion_status_and_prompt_stats() {
    let home = make_home();
    let store = Store::open(&home.join("test.sqlite"));
    let suggestion = sample_suggestion(&home, SuggestionStatus::Dismissed);
    store.save(&suggestion);
    let saved = store.saved_suggestions();
    assert_eq!(saved.first().map(|suggestion| suggestion.status), Some(SuggestionStatus::Dismissed));
    assert_eq!(saved.first(), Some(&suggestion));
    store.record_prompts(&[
        UserPrompt { timestamp: Some(now()), ..prompt("Non, jamais ça.", "/p") },
        UserPrompt { timestamp: Some(now()), ..prompt("Ajoute une page", "/p") },
    ]);
    let today = store.daily_prompt_stats(now() - chrono::Duration::seconds(3600));
    assert_eq!(today.values().next(), Some(&(2, 1)));
    store.set_setting("k", "v");
    assert_eq!(store.setting("k").as_deref(), Some("v"));
    assert_eq!(store.setting("missing"), None);
    let found = store.search_prompts("page", 50);
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].text, "Ajoute une page");
    store.record_usage(&[ProviderUsage::new(Harness::Claude, UsageState::Ok)]);
}

#[test]
fn store_decodes_legacy_swift_payloads() {
    let home = make_home();
    let path = home.join("legacy.sqlite");
    let store = Store::open(&path);
    let legacy_rule = r#"{"id":"legacy-rule","kind":"learnedRule","title":"T","rationale":"R","project":"p","filePath":"/tmp/x/CLAUDE.md","operation":{"appendRule":{"_0":"Rule."}},"evidence":[{"quote":"q","harness":"codex","sessionId":"s","date":781000000}],"status":"applied","createdAt":781000000.5}"#;
    let legacy_fix = r#"{"id":"legacy-fix","kind":"setupFix","title":"F","rationale":"R","project":"Global","filePath":"/tmp/x/SKILL.md","operation":{"addFrontmatter":{"name":"n","description":"d"}},"evidence":[],"status":"new","createdAt":781000000,"refinedRule":"Better."}"#;
    let legacy_lines = r#"{"id":"legacy-lines","kind":"setupFix","title":"L","rationale":"R","project":"Global","filePath":"/tmp/x/CLAUDE.md","operation":{"removeLines":{"_0":["@a.md","@b.md"]}},"evidence":[],"status":"saved","createdAt":781000000}"#;
    {
        let connection = rusqlite::Connection::open(&path).unwrap();
        for (id, payload) in [("legacy-rule", legacy_rule), ("legacy-fix", legacy_fix), ("legacy-lines", legacy_lines), ("bad", "garbage")] {
            connection
                .execute(
                    "INSERT INTO suggestions (id, status, updated_at, payload) VALUES (?, 'new', 0, ?)",
                    rusqlite::params![id, payload.as_bytes()],
                )
                .unwrap();
        }
    }
    let mut saved = store.saved_suggestions();
    saved.sort_by(|a, b| a.id.cmp(&b.id));
    assert_eq!(saved.len(), 3);
    assert_eq!(saved[0].id, "legacy-fix");
    assert_eq!(saved[0].operation, SuggestionOperation::AddFrontmatter { name: "n".into(), description: "d".into() });
    assert_eq!(saved[0].refined_rule.as_deref(), Some("Better."));
    assert_eq!(saved[1].operation, SuggestionOperation::RemoveLines { lines: vec!["@a.md".into(), "@b.md".into()] });
    assert_eq!(saved[1].status, SuggestionStatus::Saved);
    assert_eq!(saved[2].operation, SuggestionOperation::AppendRule { rule: "Rule.".into() });
    assert_eq!(saved[2].status, SuggestionStatus::Applied);
    assert_eq!(saved[2].created_at.timestamp(), 1_759_307_200);
    assert_eq!(saved[2].evidence[0].harness, Harness::Codex);
    assert_eq!(saved[2].evidence[0].date.map(|date| date.timestamp()), Some(1_759_307_200));
}

#[test]
fn suggestion_json_shape_is_camel_case_and_tagged() {
    let home = make_home();
    let suggestion = sample_suggestion(&home, SuggestionStatus::New);
    let value = serde_json::to_value(&suggestion).unwrap();
    assert_eq!(value["operation"], serde_json::json!({"type": "appendRule", "rule": "Rule."}));
    assert_eq!(value["kind"], "learnedRule");
    assert_eq!(value["status"], "new");
    assert!(value.get("filePath").is_some());
    assert!(value["evidence"][0].get("sessionId").is_some());
}

#[test]
fn parses_claude_usage_windows() {
    let _home = make_home();
    let data = br#"{"five_hour":{"utilization":12.5,"resets_at":"2026-10-10T08:00:00Z"},"seven_day":{"utilization":40,"resets_at":null},"extra_usage":{"is_enabled":false}}"#;
    let windows = usage::parse_claude_windows(data);
    assert_eq!(windows.iter().map(|window| window.label.as_str()).collect::<Vec<_>>(), vec!["5 h", "Week"]);
    assert_eq!(windows[0].used_percent, 12.5);
    assert!(windows[0].resets_at.is_some());
    assert_eq!(windows[0].window_minutes, Some(300));
    assert_eq!(windows[1].window_minutes, Some(10080));
    assert!(windows[1].resets_at.is_none());
}

#[test]
fn rule_writer_rejects_cli_errors_and_cleans_rules() {
    let _home = make_home();
    assert!(rule_writer::looks_like_error("Failed to authenticate: OAuth session expired and could not be refreshed."));
    assert!(!rule_writer::looks_like_error("Toujours lancer les tests."));
    assert_eq!(
        rule_writer::clean("- « Toujours lancer les tests avant de pousser »\n").as_deref(),
        Some("Toujours lancer les tests avant de pousser.")
    );
    assert_eq!(rule_writer::clean("NONE"), None);
    assert_eq!(rule_writer::clean("   \n"), None);
}

#[test]
fn rule_writer_prompt_quotes_the_evidence() {
    let home = make_home();
    let prompt = rule_writer::prompt_for(&sample_suggestion(&home, SuggestionStatus::New));
    assert!(prompt.starts_with(
        "A developer had to correct their coding agent. Here are their messages:\n- The developer wrote: \"Non, jamais ça.\"\n  right after the agent said: \"ok\"\n\nWrite ONE general rule to add to the project's CLAUDE.md file"
    ));
    assert!(prompt.ends_with("Answer with the rule only, no quotes or bullet."));
}

#[test]
fn parses_cursor_token_and_usage() {
    let _home = make_home();
    assert_eq!(cursor_auth::user_id(&jwt(r#"{"sub":"auth0|user_42"}"#)).as_deref(), Some("user_42"));
    let data = br#"{"gpt-4":{"numRequests":250,"maxRequestUsage":500},"startOfMonth":"2026-10-01T00:00:00.000Z"}"#;
    let windows = usage::parse_cursor_windows(data);
    assert_eq!(windows.len(), 1);
    assert_eq!(windows[0].used_percent, 50.0);
    assert_eq!(windows[0].label, "gpt-4 requests");
    assert!(windows[0].resets_at.is_some());
}

#[test]
fn reads_cursor_summary_and_utf16_tokens() {
    let _home = make_home();
    let summary = br#"{"billingCycleEnd":"2026-11-01T00:00:00.000Z","membershipType":"pro","individualUsage":{"plan":{"used":1200,"limit":2000,"autoPercentUsed":40,"apiPercentUsed":80},"onDemand":{"used":500,"limit":1000}}}"#;
    let (plan, windows) = usage::parse_cursor_summary(summary).unwrap();
    assert_eq!(plan.as_deref(), Some("pro"));
    assert_eq!(windows.iter().map(|window| window.used_percent).collect::<Vec<_>>(), vec![60.0, 50.0]);
    assert!(windows[0].resets_at.is_some());
    let utf16: Vec<u8> = "abc.def.ghi".encode_utf16().flat_map(u16::to_le_bytes).collect();
    assert_eq!(cursor_auth::decode(&utf16).as_deref(), Some("abc.def.ghi"));
    assert_eq!(cursor_auth::decode(b"\"abc.def\"").as_deref(), Some("abc.def"));
    assert!(!cursor_auth::is_usable(&jwt(r#"{"sub":"auth0|u1","exp":1000}"#)));
    assert!(cursor_auth::is_usable(&jwt(r#"{"sub":"auth0|u1","exp":4102444800}"#)));
    assert!(!cursor_auth::is_usable("not-a-jwt"));
}

#[test]
fn reads_cursor_token_from_the_app_database() {
    let _home = make_home();
    let token = jwt(r#"{"sub":"auth0|u7","exp":4102444800}"#);
    let database = cursor_auth::app_database();
    std::fs::create_dir_all(database.parent().unwrap()).unwrap();
    let connection = rusqlite::Connection::open(&database).unwrap();
    connection.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)", []).unwrap();
    let utf16: Vec<u8> = format!("\"{token}\"").encode_utf16().flat_map(u16::to_le_bytes).collect();
    connection
        .execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', ?)", rusqlite::params![utf16])
        .unwrap();
    drop(connection);
    assert!(cursor_auth::is_installed());
    assert_eq!(cursor_auth::usable_token(), Some(token.clone()));
    assert_eq!(cursor_auth::user_id(&token).as_deref(), Some("u7"));
}

#[test]
fn builds_local_domain_model() {
    let home = make_home();
    let project = git_project(&home, "shop");
    write(
        "# Shop\n\n- Use pnpm for everything.\n- Prices are stored in cents.\n\n## Règles apprises\n\n- Toujours écrire le test d'abord.\n",
        &project.join("CLAUDE.md"),
    );
    write("- Use pnpm for everything.\n", &project.join("AGENTS.md"));
    let session = AgentSession::new(Harness::Codex, "c", "Checkout refactor", path_str(&project.join("src")), AgentStatus::Working, now());
    let root = path_str(&project);
    let model = domain::build(&root, "Sell socks.", std::slice::from_ref(&session), &[]);
    assert!(model.conventions.iter().any(|fact| fact.text == "Prices are stored in cents."));
    assert_eq!(model.decisions.iter().map(|fact| fact.text.as_str()).collect::<Vec<_>>(), vec!["Toujours écrire le test d'abord."]);
    assert_eq!(model.activity.iter().map(|fact| fact.text.as_str()).collect::<Vec<_>>(), vec!["Checkout refactor"]);
    assert_eq!(model.agents.get(&Harness::Codex), Some(&1));
    assert_eq!(model.conflicts.len(), 1);
    assert!(model.markdown.contains("## Intent\n\nSell socks."));
    assert_eq!(domain::projects(std::slice::from_ref(&session)), vec![root.clone()]);
    assert_eq!(model.export_diff.first().map(|line| line.text.as_str()), Some("--- /dev/null"));
    assert_eq!(model.export_diff.get(1).map(|line| line.text.as_str()), Some("+++ b/.boss/domain.md"));

    domain::export(&model).unwrap();
    assert_eq!(std::fs::read_to_string(project.join(".boss/domain.md")).unwrap(), model.markdown);
    let rebuilt = domain::build(&root, "Sell socks.", &[session], &[]);
    assert!(rebuilt.export_diff.is_empty());
    let json = serde_json::to_value(&rebuilt).unwrap();
    assert_eq!(json["agents"]["codex"], 1);
    assert!(json.get("exportPath").is_some());
}

#[test]
fn claude_usage_gauge_end_to_end_with_stubbed_api() {
    let home = make_home();
    std::fs::create_dir_all(Paths::claude()).unwrap();
    let stub = Stub::start(200, CLAUDE_USAGE);
    let client = ClaudeUsageClient::new(&stub.url, found(CREDENTIALS));
    let claude = client.usage(true);
    assert_eq!(claude.state, UsageState::Ok);
    assert_eq!(claude.plan.as_deref(), Some("team"));
    assert_eq!(claude.windows.iter().map(|window| window.used_percent).collect::<Vec<_>>(), vec![37.0, 12.0]);
    assert_eq!(stub.last_authorization().as_deref(), Some("Bearer tok-123"));

    stub.set(401, "{}");
    let expired = ClaudeUsageClient::new(&stub.url, found(CREDENTIALS)).usage(true);
    assert_eq!(expired.state, UsageState::TokenExpired);
    assert_eq!(expired.plan.as_deref(), Some("team"));

    stub.set(500, "{}");
    let failing = ClaudeUsageClient::new(&stub.url, found(CREDENTIALS)).usage(true);
    assert_eq!(failing.state, UsageState::Failed("HTTP 500 response from Anthropic.".into()));

    let missing = ClaudeUsageClient::new(&stub.url, Arc::new(|| KeychainResult::Missing)).usage(true);
    assert_eq!(missing.state, UsageState::SignedOut);
    let blocked = ClaudeUsageClient::new(&stub.url, Arc::new(|| KeychainResult::Blocked)).usage(true);
    assert_eq!(blocked.state, UsageState::KeychainBlocked);
    let garbage = ClaudeUsageClient::new(&stub.url, found("{}")).usage(true);
    assert_eq!(garbage.state, UsageState::SignedOut);

    std::fs::remove_dir_all(home.join(".claude")).unwrap();
    let not_installed = ClaudeUsageClient::new(&stub.url, found(CREDENTIALS)).usage(true);
    assert_eq!(not_installed.state, UsageState::NotInstalled);
}

#[test]
fn claude_usage_keeps_the_last_good_reading_while_throttled() {
    let _home = make_home();
    std::fs::create_dir_all(Paths::claude()).unwrap();
    let stub = Stub::start(200, CLAUDE_USAGE);
    let client = ClaudeUsageClient::new(&stub.url, found(CREDENTIALS));
    assert_eq!(client.usage(true).state, UsageState::Ok);
    assert_eq!(client.usage(false).state, UsageState::Ok);
    assert_eq!(stub.hits(), 1);

    stub.set(429, "{}");
    let throttled = client.usage(true);
    assert_eq!(throttled.state, UsageState::Ok);
    assert_eq!(throttled.windows.len(), 2);
    assert_eq!(stub.hits(), 2);
    client.usage(true);
    assert_eq!(stub.hits(), 2);

    client.forget_credentials();
    let unreachable = ClaudeUsageClient::new("http://127.0.0.1:1/usage", found(CREDENTIALS)).usage(true);
    assert!(matches!(unreachable.state, UsageState::Failed(message) if message.starts_with("Network unavailable: ")));
}

#[test]
fn claude_usage_rolls_over_a_window_whose_reset_passed_while_throttled() {
    let _home = make_home();
    std::fs::create_dir_all(Paths::claude()).unwrap();
    let soon = (now() + chrono::Duration::milliseconds(1500)).to_rfc3339();
    let body = format!(
        r#"{{"five_hour":{{"utilization":100,"resets_at":"{soon}"}},"seven_day":{{"utilization":34,"resets_at":"2099-10-14T00:00:00Z"}}}}"#
    );
    let stub = Stub::start(200, &body);
    let client = ClaudeUsageClient::new(&stub.url, found(CREDENTIALS));
    let before = client.usage(true);
    assert_eq!(before.windows.iter().map(|window| window.used_percent).collect::<Vec<_>>(), vec![100.0, 34.0]);

    std::thread::sleep(std::time::Duration::from_millis(1600));
    stub.set(429, "{}");
    let after = client.usage(true);
    assert_eq!(after.state, UsageState::Ok);
    assert_eq!(after.windows.iter().map(|window| window.used_percent).collect::<Vec<_>>(), vec![0.0, 34.0]);
    assert!(after.windows[0].resets_at.is_none());
    assert!(after.windows[1].resets_at.is_some());
    assert_eq!(client.usage(false).windows[0].used_percent, 0.0);
}

#[test]
fn claude_usage_report_through_usage_service() {
    let _home = make_home();
    std::fs::create_dir_all(Paths::claude()).unwrap();
    let stub = Stub::start(200, CLAUDE_USAGE);
    let monitor = Arc::new(AgentMonitor::new(false));
    let options = UsageOptions {
        endpoints: UsageEndpoints { claude_usage: stub.url.clone(), ..UsageEndpoints::default() },
        read_credentials: found(CREDENTIALS),
    };
    let service = UsageService::with_options(monitor.clone(), monitor.clone(), options);
    let report = service.report(true);
    let claude = report.providers.iter().find(|provider| provider.harness == Harness::Claude).unwrap();
    assert_eq!(claude.state, UsageState::Ok);
    assert_eq!(claude.plan.as_deref(), Some("team"));
    assert_eq!(stub.last_authorization().as_deref(), Some("Bearer tok-123"));
    assert_eq!(service.codex_usage().state, UsageState::NotInstalled);

    stub.set(401, "{}");
    let options = UsageOptions {
        endpoints: UsageEndpoints { claude_usage: stub.url.clone(), ..UsageEndpoints::default() },
        read_credentials: found(CREDENTIALS),
    };
    let expired = UsageService::with_options(monitor.clone(), monitor.clone(), options).report(true);
    assert_eq!(expired.providers.iter().find(|provider| provider.harness == Harness::Claude).unwrap().state, UsageState::TokenExpired);

    let options = UsageOptions {
        endpoints: UsageEndpoints { claude_usage: stub.url.clone(), ..UsageEndpoints::default() },
        read_credentials: Arc::new(|| KeychainResult::Missing),
    };
    let missing = UsageService::with_options(monitor.clone(), monitor, options).report(true);
    assert_eq!(missing.providers.iter().find(|provider| provider.harness == Harness::Claude).unwrap().state, UsageState::SignedOut);
}

#[test]
fn reads_claude_credentials_file() {
    let _home = make_home();
    assert_eq!(usage::read_credentials_file(), KeychainResult::Missing);
    write(CREDENTIALS, &usage::credentials_file());
    let KeychainResult::Found(data) = usage::read_credentials_file() else { panic!("credentials file not read") };
    let credentials = usage::decode_credentials(&data).unwrap();
    assert_eq!(credentials.access_token, "tok-123");
    assert_eq!(credentials.subscription.as_deref(), Some("team"));
    assert_eq!(credentials.expires_at.map(|date| date.timestamp()), Some(4_102_444_800));
}

#[test]
fn usage_types_serialize_for_the_ui() {
    let _home = make_home();
    assert_eq!(serde_json::to_value(UsageState::Ok).unwrap(), serde_json::json!({"kind": "ok"}));
    assert_eq!(
        serde_json::to_value(UsageState::Failed("boom".into())).unwrap(),
        serde_json::json!({"kind": "failed", "message": "boom"})
    );
    assert_eq!(serde_json::to_value(UsageState::KeychainBlocked).unwrap(), serde_json::json!({"kind": "keychainBlocked"}));
    let provider = serde_json::to_value(ProviderUsage::new(Harness::Codex, UsageState::NoData)).unwrap();
    assert!(provider.get("observedAt").is_some());
    assert_eq!(UsageState::SignedOut.fix_steps().len(), 3);
    assert_eq!(UsageState::Ok.problem(), None);
    let report = usage::UsageReport {
        providers: Vec::new(),
        daily: vec![
            DailyTokens { day: day_key(now()), harness: Harness::Claude, tokens: TokenUsage::new(1, 2, 3, 4) },
            DailyTokens { day: "2000-01-01".into(), harness: Harness::Claude, tokens: TokenUsage::new(5, 0, 0, 0) },
        ],
    };
    assert_eq!(report.today().total(), 10);
    assert_eq!(report.tokens_last_days(7).total(), 10);
    assert_eq!(report.tokens_on("2000-01-01").total(), 5);
}

#[test]
fn builds_analytics_from_the_store() {
    let home = make_home();
    let store = Store::open(&home.join("analytics.sqlite"));
    store.record_prompts(&[
        UserPrompt { timestamp: Some(now()), ..prompt("Non, jamais ça.", "/p") },
        UserPrompt { timestamp: Some(now()), ..prompt("Ajoute une page", "/p") },
        UserPrompt { timestamp: Some(now()), ..prompt("Ajoute un test", "/p") },
    ]);
    let daily = [DailyTokens { day: day_key(now()), harness: Harness::Codex, tokens: TokenUsage::new(10, 5, 0, 0) }];
    let report = analytics::build(&store, &daily, analytics::DEFAULT_DAYS, now());
    assert_eq!(report.days.len(), 28);
    let today = report.days.last().unwrap();
    assert_eq!(today.day, day_key(now()));
    assert_eq!((today.prompts, today.corrections, today.tokens), (3, 1, 15));
    assert_eq!(report.prompts_this_week, 3);
    assert_eq!(report.corrections_this_week, 1);
    assert_eq!(report.trend, Trend::NotEnoughData);
    assert_eq!(serde_json::to_value(report.trend).unwrap(), serde_json::json!({"kind": "notEnoughData"}));
}

#[test]
fn computes_analytics_trends() {
    let _home = make_home();
    let day = |prompts: i64, corrections: i64| analytics::DayStat { day: "d".into(), prompts, corrections, tokens: 0 };
    assert_eq!(analytics::trend(&[day(10, 0)], &[day(10, 3)]), Trend::Improving { delta: 0.3 });
    assert!(matches!(analytics::trend(&[day(10, 3)], &[day(10, 0)]), Trend::Degrading { .. }));
    assert_eq!(analytics::trend(&[day(10, 1)], &[day(10, 1)]), Trend::Stable);
    assert_eq!(analytics::trend(&[day(9, 1)], &[day(10, 1)]), Trend::NotEnoughData);
    assert_eq!(
        serde_json::to_value(Trend::Improving { delta: 0.5 }).unwrap(),
        serde_json::json!({"kind": "improving", "delta": 0.5})
    );
}

#[test]
fn builds_resume_commands() {
    let _home = make_home();
    let mut session = AgentSession::new(Harness::Claude, "abc", "t", "", AgentStatus::Finished, now());
    assert_eq!(launcher::resume_command(&session), "claude --resume abc");
    session.harness = Harness::Pi;
    assert_eq!(launcher::resume_command(&session), "pi --continue");
    session.harness = Harness::Cursor;
    session.cwd = "/work/it's".into();
    let quoted = if cfg!(windows) { "\"/work/it's\"" } else { "'/work/it'\\''s'" };
    assert_eq!(launcher::resume_command(&session), format!("cd {quoted} && cursor-agent resume abc"));
    assert_eq!(launcher::posix_quote("a'b"), "'a'\\''b'");
    assert_eq!(
        launcher::app_bundle("/Applications/Cursor.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper").as_deref(),
        Some("/Applications/Cursor.app")
    );
    assert_eq!(launcher::app_bundle("/usr/local/bin/claude"), None);
    let script = launcher::linux_login_script("/opt/claude");
    assert!(script.starts_with("'/opt/claude' auth login; echo; echo 'You can close this window and go back to The Boss.'; read _"));
    assert_eq!(launcher::linux_terminal_commands(&script).len(), 7);
}

struct EnglishOnDrop;

impl Drop for EnglishOnDrop {
    fn drop(&mut self) {
        set_language(AppLanguage::English);
    }
}

#[test]
fn translates_to_french_on_demand() {
    let _home = make_home();
    let _reset = EnglishOnDrop;
    set_language(AppLanguage::French);
    assert_eq!(boss_core::trf!("Remove %d broken imports", 3), "Retirer 3 imports cassés");
    assert_eq!(SuggestionEngine::appending("Règle.", "## Learned rules\n\n- A.\n"), "## Learned rules\n\n- A.\n- Règle.\n");
    assert_eq!(SuggestionEngine::appending("Règle.", ""), "## Règles apprises\n\n- Règle.\n");
}

#[test]
fn shared_services_are_thread_safe() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<Store>();
    assert_send_sync::<ClaudeUsageClient>();
    assert_send_sync::<UsageService>();
}
