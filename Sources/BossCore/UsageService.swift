import Foundation

public enum UsageState: Hashable, Sendable {
    case ok
    case notInstalled
    case signedOut
    case keychainBlocked
    case tokenExpired
    case noData
    case failed(String)

    public var problem: String? {
        switch self {
        case .ok: nil
        case .notInstalled: "Pas installé sur ce Mac."
        case .signedOut: "Claude Code n'est pas connecté."
        case .keychainBlocked: "macOS bloque la lecture du trousseau."
        case .tokenExpired: "Le jeton de connexion a expiré."
        case .noData: "Pas encore de données d'usage."
        case .failed(let message): message
        }
    }

    public var fixSteps: [String] {
        switch self {
        case .signedOut:
            ["Ouvre un terminal et lance `claude auth status --text`.",
             "S'il dit « not logged in », lance `claude auth login`.",
             "Reviens ici : la jauge se remplit au prochain passage."]
        case .keychainBlocked:
            ["Ouvre Trousseaux d'accès et cherche « Claude Code-credentials ».",
             "Onglet Contrôle d'accès : ajoute The Boss à « Toujours autoriser l'accès par ces applications ».",
             "S'il y a plusieurs éléments qui commencent par ce nom, fais-le pour chacun.",
             "Ça ne change rien à ton compte Claude et ne te connecte pas."]
        case .tokenExpired:
            ["Clique « Réparer automatiquement » : Claude Code rafraîchit son jeton.",
             "Si ça échoue, lance `claude auth login` dans un terminal.",
             "Reviens ici : la jauge se met à jour toute seule."]
        case .noData:
            ["Lance une session : les limites arrivent avec la première réponse de l'agent."]
        default: []
        }
    }
}

public struct ProviderUsage: Hashable, Sendable {
    public var harness: Harness
    public var state: UsageState
    public var plan: String?
    public var windows: [RateWindow]
    public var observedAt: Date?

    public init(harness: Harness, state: UsageState, plan: String? = nil, windows: [RateWindow] = [], observedAt: Date? = nil) {
        self.harness = harness
        self.state = state
        self.plan = plan
        self.windows = windows
        self.observedAt = observedAt
    }
}

public struct UsageReport: Sendable {
    public var providers: [ProviderUsage]
    public var daily: [DailyTokens]

    public init(providers: [ProviderUsage], daily: [DailyTokens]) {
        self.providers = providers
        self.daily = daily
    }

    public func tokens(on day: String) -> TokenUsage {
        daily.filter { $0.day == day }.reduce(TokenUsage()) { $0 + $1.tokens }
    }

    public func tokens(lastDays: Int) -> TokenUsage {
        let cutoff = DayKey.of(Date().addingTimeInterval(-Double(lastDays - 1) * 86400))
        return daily.filter { $0.day >= cutoff }.reduce(TokenUsage()) { $0 + $1.tokens }
    }

    public var today: TokenUsage { tokens(on: DayKey.of(Date())) }
}

struct ClaudeCredentials {
    var accessToken: String
    var expiresAt: Date?
    var subscription: String?
}

enum KeychainResult {
    case found(Data)
    case missing
    case blocked
}

public final class UsageService: @unchecked Sendable {
    private let monitor: AgentMonitor
    private let liveMonitor: AgentMonitor
    private var cachedCredentials: ClaudeCredentials?
    private var lastClaude: ProviderUsage?
    private var lastClaudeFetch: Date?
    private var lastGood: ProviderUsage?
    private var backoffUntil: Date?
    static let throttledPrefix = "Anthropic limite"
    private let session: URLSession
    private let readCredentials: () -> KeychainResult

    public convenience init(monitor: AgentMonitor, liveMonitor: AgentMonitor? = nil, session: URLSession = .shared) {
        self.init(monitor: monitor, liveMonitor: liveMonitor, session: session,
                  readCredentials: { UsageService.readKeychain(servicePrefix: "Claude Code-credentials") })
    }

    init(monitor: AgentMonitor, liveMonitor: AgentMonitor?, session: URLSession, readCredentials: @escaping () -> KeychainResult) {
        self.readCredentials = readCredentials
        self.monitor = monitor
        self.liveMonitor = liveMonitor ?? monitor
        self.session = session
    }

    public func report(force: Bool = false) async -> UsageReport {
        let claude = await claudeUsage(force: force)
        let codex = codexUsage()
        var providers = [claude, codex]
        if let cursor = await cursorUsage() { providers.append(cursor) }
        let daily = monitor.dailyTokens(within: 30 * 86400)
        return UsageReport(providers: providers, daily: daily)
    }

    public func codexUsage() -> ProviderUsage {
        guard FileManager.default.fileExists(atPath: Paths.codex.path) else {
            return ProviderUsage(harness: .codex, state: .notInstalled)
        }
        guard let snapshot = liveMonitor.codexRateLimits() else {
            return ProviderUsage(harness: .codex, state: .noData)
        }
        let windows = snapshot.windows.map { window -> RateWindow in
            var copy = window
            if let reset = window.resetsAt, reset < Date() { copy.usedPercent = 0 }
            return copy
        }
        return ProviderUsage(harness: .codex, state: .ok, plan: snapshot.plan, windows: windows, observedAt: snapshot.observedAt)
    }

    public func forgetClaudeCredentials() {
        cachedCredentials = nil
        lastClaudeFetch = nil
    }

    func claudeUsage(force: Bool) async -> ProviderUsage {
        guard FileManager.default.fileExists(atPath: Paths.claude.path) else {
            return ProviderUsage(harness: .claude, state: .notInstalled)
        }
        if let backoffUntil, Date() < backoffUntil, let lastClaude { return lastClaude }
        if !force, let lastClaude, let lastClaudeFetch, Date().timeIntervalSince(lastClaudeFetch) < 120 {
            return lastClaude
        }
        var result = await fetchClaude()
        lastClaudeFetch = Date()
        if case .failed(let message) = result.state, message.hasPrefix(Self.throttledPrefix) {
            backoffUntil = Date().addingTimeInterval(300)
            if let lastGood, lastGood.state == .ok {
                result = lastGood
            }
        } else {
            backoffUntil = nil
        }
        if result.state == .ok { lastGood = result }
        lastClaude = result
        return result
    }

    private func fetchClaude() async -> ProviderUsage {
        if cachedCredentials == nil {
            switch readCredentials() {
            case .missing:
                return ProviderUsage(harness: .claude, state: .signedOut)
            case .blocked:
                return ProviderUsage(harness: .claude, state: .keychainBlocked)
            case .found(let data):
                guard let credentials = Self.decodeCredentials(data) else {
                    return ProviderUsage(harness: .claude, state: .signedOut)
                }
                cachedCredentials = credentials
            }
        }
        guard let credentials = cachedCredentials else { return ProviderUsage(harness: .claude, state: .signedOut) }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                cachedCredentials = nil
                return ProviderUsage(harness: .claude, state: .tokenExpired, plan: credentials.subscription)
            }
            if code == 429 {
                return ProviderUsage(harness: .claude, state: .failed("\(Self.throttledPrefix) les lectures d'usage. Nouvel essai dans 5 min."), plan: credentials.subscription)
            }
            guard code == 200 else {
                return ProviderUsage(harness: .claude, state: .failed("Réponse HTTP \(code) de Anthropic."), plan: credentials.subscription)
            }
            let windows = Self.parseClaudeWindows(data)
            return ProviderUsage(harness: .claude, state: .ok, plan: credentials.subscription, windows: windows, observedAt: Date())
        } catch {
            return ProviderUsage(harness: .claude, state: .failed("Réseau indisponible : \(error.localizedDescription)"), plan: credentials.subscription)
        }
    }

    func cursorUsage() async -> ProviderUsage? {
        guard CursorAuth.isInstalled else { return nil }
        guard let token = CursorAuth.usableToken(), let user = CursorAuth.userId(fromJWT: token) else {
            return ProviderUsage(harness: .cursor, state: .failed("Cursor n'est pas connecté (ou sa session a expiré) : ouvre Cursor pour te reconnecter."))
        }
        let cookie = "WorkosCursorSessionToken=\(user)%3A%3A\(token)"
        do {
            let (summaryData, summaryCode) = try await cursorGet("https://cursor.com/api/usage-summary", cookie: cookie)
            if summaryCode == 401 || summaryCode == 403 {
                return ProviderUsage(harness: .cursor, state: .failed("Cursor refuse la session : reconnecte-toi dans Cursor."))
            }
            if summaryCode == 200, let parsed = Self.parseCursorSummary(summaryData), !parsed.windows.isEmpty {
                return ProviderUsage(harness: .cursor, state: .ok, plan: parsed.plan, windows: parsed.windows, observedAt: Date())
            }
            let (legacyData, legacyCode) = try await cursorGet("https://cursor.com/api/usage?user=\(user)", cookie: cookie)
            guard legacyCode == 200 else {
                return ProviderUsage(harness: .cursor, state: .failed("Réponse HTTP \(legacyCode) de Cursor."))
            }
            let windows = Self.parseCursorWindows(legacyData)
            return ProviderUsage(harness: .cursor, state: windows.isEmpty ? .noData : .ok, windows: windows, observedAt: Date())
        } catch {
            return ProviderUsage(harness: .cursor, state: .failed("Réseau indisponible : \(error.localizedDescription)"))
        }
    }

    private func cursorGet(_ url: String, cookie: String) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func parseCursorSummary(_ data: Data) -> (plan: String?, windows: [RateWindow])? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let reset = ISODate.parse(json["billingCycleEnd"])
        let individual = json["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        func number(_ dict: [String: Any]?, _ key: String) -> Double? { (dict?[key] as? NSNumber)?.doubleValue }
        func ratio(_ dict: [String: Any]?) -> Double? {
            guard let used = number(dict, "used"), let limit = number(dict, "limit"), limit > 0 else { return nil }
            return used / limit * 100
        }
        var windows: [RateWindow] = []
        let auto = number(plan, "autoPercentUsed")
        let api = number(plan, "apiPercentUsed")
        let planPercent = number(plan, "totalPercentUsed")
            ?? ((auto != nil && api != nil) ? (auto! + api!) / 2 : (api ?? auto))
            ?? ratio(plan)
            ?? ratio(individual?["overall"] as? [String: Any])
            ?? ratio((json["teamUsage"] as? [String: Any])?["pooled"] as? [String: Any])
        if let planPercent {
            windows.append(RateWindow(label: "Forfait du mois", usedPercent: min(100, max(0, planPercent)), resetsAt: reset, windowMinutes: nil))
        }
        if let onDemand = ratio(individual?["onDemand"] as? [String: Any]) {
            windows.append(RateWindow(label: "À la demande", usedPercent: min(100, max(0, onDemand)), resetsAt: reset, windowMinutes: nil))
        }
        return (json["membershipType"] as? String, windows)
    }

    static func parseCursorWindows(_ data: Data) -> [RateWindow] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let start = ISODate.parse(json["startOfMonth"])
        let reset = start.flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }
        return json.keys.sorted().compactMap { key in
            guard let model = json[key] as? [String: Any],
                  let used = (model["numRequests"] as? NSNumber)?.doubleValue,
                  let max = (model["maxRequestUsage"] as? NSNumber)?.doubleValue, max > 0 else { return nil }
            return RateWindow(label: "Requêtes \(key)", usedPercent: min(100, used / max * 100), resetsAt: reset, windowMinutes: nil)
        }
    }

    static func parseClaudeWindows(_ data: Data) -> [RateWindow] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let order = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_oauth_apps"]
        let labels = ["five_hour": "5 h", "seven_day": "Semaine", "seven_day_opus": "Semaine · Opus",
                      "seven_day_sonnet": "Semaine · Sonnet", "seven_day_oauth_apps": "Semaine · Apps"]
        let keys = json.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
        return keys.compactMap { key in
            guard let window = json[key] as? [String: Any],
                  let utilization = (window["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let minutes = key == "five_hour" ? 300 : (key.hasPrefix("seven_day") ? 10080 : nil)
            return RateWindow(label: labels[key] ?? key.replacingOccurrences(of: "_", with: " "),
                              usedPercent: utilization, resetsAt: ISODate.parse(window["resets_at"]), windowMinutes: minutes)
        }
    }

    static func decodeCredentials(_ data: Data) -> ClaudeCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        return ClaudeCredentials(accessToken: token, expiresAt: ISODate.parse(oauth["expiresAt"]),
                                 subscription: oauth["subscriptionType"] as? String)
    }

    static func readKeychain(servicePrefix: String) -> KeychainResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", servicePrefix, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return .blocked
        }
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning {
            process.terminate()
            return .blocked
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        switch process.terminationStatus {
        case 0:
            let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .missing : .found(Data(trimmed.utf8))
        case 44:
            return .missing
        default:
            return .blocked
        }
    }
}
