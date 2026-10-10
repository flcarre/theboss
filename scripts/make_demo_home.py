import json
import pathlib
import sys
import time
import uuid
from datetime import datetime, timedelta, timezone

home = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/demo-home").resolve()
now = datetime.now(timezone.utc)


def stamp(minutes_ago=0):
    return (now - timedelta(minutes=minutes_ago)).isoformat().replace("+00:00", "Z")


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n" for row in rows))


claude_sessions = [
    ("waiting", "api-payments", "Migrer la base vers Postgres 17", "Lance la migration et vérifie les index.", "Bash", "psql -f migrations/017_postgres17.sql"),
    ("busy", "web-dashboard", "Refonte du tableau de bord", "Refais la page d'accueil avec les nouveaux composants.", None, None),
    ("busy", "mobile-app", "Corriger le crash au démarrage", "Non, je t'ai dit de toujours écrire un test qui reproduit le bug avant de corriger.", None, None),
    ("idle", "docs-site", "Mettre à jour la doc d'installation", "Ajoute la section Windows.", None, None),
]
(home / ".claude/sessions").mkdir(parents=True, exist_ok=True)
for index, (status, project, title, prompt, tool, command) in enumerate(claude_sessions):
    session_id = str(uuid.uuid4())
    cwd = str(home / "code" / project)
    (home / "code" / project / ".git").mkdir(parents=True, exist_ok=True)
    (home / ".claude/sessions" / f"{index + 1}.json").write_text(json.dumps({
        "pid": 1, "sessionId": session_id, "cwd": cwd, "name": title, "status": status,
        "startedAt": int((time.time() - 3600) * 1000), "updatedAt": int(time.time() * 1000), "kind": "interactive"}))
    rows = [
        {"type": "user", "sessionId": session_id, "cwd": cwd, "timestamp": stamp(30), "message": {"role": "user", "content": prompt}},
        {"type": "assistant", "timestamp": stamp(29), "message": {"id": f"m{index}", "model": "claude-opus-5-5",
         "content": [{"type": "text", "text": "Je m'en occupe."}], "usage": {"input_tokens": 1200 * (index + 1), "output_tokens": 800}}},
    ]
    if tool:
        rows.append({"type": "assistant", "timestamp": stamp(1), "message": {"id": f"t{index}", "model": "claude-opus-5-5",
                     "content": [{"type": "tool_use", "id": f"tool{index}", "name": tool, "input": {"command": command}}],
                     "usage": {"input_tokens": 10, "output_tokens": 10}}})
    encoded = cwd.replace("/", "-").replace(".", "-")
    write_jsonl(home / ".claude/projects" / encoded / f"{session_id}.jsonl", rows)

rollout = home / ".codex/sessions" / now.strftime("%Y/%m/%d") / "rollout-demo.jsonl"
cwd = str(home / "code" / "data-pipeline")
(home / "code" / "data-pipeline" / ".git").mkdir(parents=True, exist_ok=True)
(home / "code" / "data-pipeline" / "CLAUDE.md").write_text("# Data pipeline\n\n@docs/conventions.md\n")
reset = int(time.time() + 3 * 3600)
write_jsonl(rollout, [
    {"type": "session_meta", "timestamp": stamp(20), "payload": {"id": "codex-demo-1", "cwd": cwd, "timestamp": stamp(20)}},
    {"type": "event_msg", "timestamp": stamp(19), "payload": {"type": "task_started"}},
    {"type": "response_item", "timestamp": stamp(19), "payload": {"type": "message", "role": "user",
     "content": [{"type": "input_text", "text": "Accélère le job d'agrégation nocturne"}]}},
    {"type": "event_msg", "timestamp": stamp(1), "payload": {"type": "token_count",
     "info": {"total_token_usage": {"input_tokens": 52000, "cached_input_tokens": 30000, "output_tokens": 4000}},
     "rate_limits": {"primary": {"used_percent": 63.0, "window_minutes": 300, "resets_at": reset},
                     "secondary": {"used_percent": 21.0, "window_minutes": 10080, "resets_at": reset + 86400 * 3},
                     "plan_type": "plus"}}},
])
(home / ".claude/CLAUDE.md").write_text("# Mes règles\n\n- Réponds en français.\n")
(home / ".claude/settings.json").write_text(json.dumps({"hooks": {"PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "npm run lint --silent"}]}]}}))
print(home)

gemini_project = home / ".gemini/tmp/mobile-app"
(gemini_project / "chats").mkdir(parents=True, exist_ok=True)
(gemini_project / ".project_root").write_text(str(home / "code" / "mobile-app") + "\n")
write_jsonl(gemini_project / "chats" / "session-demo.jsonl", [
    {"sessionId": "gemini-demo-1", "projectHash": "demo", "startTime": stamp(40), "lastUpdated": stamp(0), "kind": "main"},
    {"id": "gu1", "timestamp": stamp(40), "type": "user", "content": [{"text": "Write the onboarding screens in SwiftUI"}]},
    {"id": "gg1", "timestamp": stamp(39), "type": "gemini", "content": "Working on the three onboarding screens.", "model": "gemini-3-pro",
     "tokens": {"input": 8000, "output": 1200, "cached": 2000, "total": 9200}},
    {"$set": {"lastUpdated": stamp(0), "summary": "Onboarding screens"}},
    {"id": "gu2", "timestamp": stamp(0), "type": "user", "content": [{"text": "Add a skip button too"}]},
])

copilot_session = home / ".copilot/session-state/copilot-demo-1"
copilot_session.mkdir(parents=True, exist_ok=True)
(copilot_session / "workspace.yaml").write_text(f"id: copilot-demo-1\ncwd: {home / 'code' / 'web-dashboard'}\nsummary: Upgrade to React 20\n")
(copilot_session / "inuse.1.lock").write_text("1")
write_jsonl(copilot_session / "events.jsonl", [
    {"id": "c1", "timestamp": stamp(15), "type": "session.start", "data": {"sessionId": "copilot-demo-1", "selectedModel": "gpt-5",
     "context": {"cwd": str(home / "code" / "web-dashboard")}}},
    {"id": "c2", "timestamp": stamp(14), "type": "user.message", "data": {"content": "Upgrade the dashboard to React 20"}},
    {"id": "c3", "timestamp": stamp(13), "type": "assistant.turn_start", "data": {"turnId": "1"}},
    {"id": "c4", "timestamp": stamp(2), "type": "permission.requested", "data": {"requestId": "p1",
     "permissionRequest": {"kind": "shell", "fullCommandText": "npm install react@20", "intention": "Install React 20"}}},
])
