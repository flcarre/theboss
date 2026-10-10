import AppKit
import BossCore

enum SessionLauncher {
    static func resumeCommand(_ session: AgentSession) -> String {
        let cd = session.cwd.isEmpty ? "" : "cd \(shellQuote(session.cwd)) && "
        switch session.harness {
        case .claude: return cd + "claude --resume \(session.sessionId)"
        case .codex: return cd + "codex resume \(session.sessionId)"
        case .gemini: return cd + "gemini --resume \(session.sessionId)"
        case .copilot: return cd + "copilot --resume \(session.sessionId)"
        case .pi: return cd + "pi --continue"
        case .omp: return cd + "omp --continue"
        case .cursor: return cd + "cursor-agent resume \(session.sessionId)"
        }
    }

    static func focus(_ session: AgentSession) -> Bool {
        if let pid = session.pid, let app = owningApplication(of: pid) {
            return app.activate()
        }
        let names: [String]
        switch session.harness {
        case .codex: names = ["Codex"]
        case .cursor: names = ["Cursor"]
        case .copilot: names = ["Visual Studio Code", "Code"]
        default: names = []
        }
        if let app = NSWorkspace.shared.runningApplications.first(where: { app in
            names.contains { app.localizedName?.localizedCaseInsensitiveContains($0) == true }
        }) {
            return app.activate()
        }
        return false
    }

    static func owningApplication(of pid: Int32) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            guard let parent = parentPid(of: current), parent > 1, parent != current else { return nil }
            current = parent
        }
        return nil
    }

    static func parentPid(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
