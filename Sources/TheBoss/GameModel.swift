import AppKit
import BossCore
import Combine
import SpriteKit
import UserNotifications

enum Panel: Equatable {
    case overview, usage, library, inbox, analytics, settings, domain
    case robot(String)
}

struct DialogChoice: Identifiable {
    let id = UUID()
    var title: String
    var action: @MainActor () -> Void
}

struct Dialog: Identifiable {
    let id = UUID()
    var speaker: String?
    var portrait: NSImage?
    var pages: [String]
    var choices: [DialogChoice] = []
}

enum MenuEntry: String, CaseIterable, Identifiable {
    case agents = "Agents"
    case inbox = "Courrier"
    case usage = "Usage"
    case rules = "Règles"
    case stats = "Stats"
    case domain = "Domaine"
    case settings = "Réglages"
    case close = "Retour"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agents: "tbfc/icons/icones_ecrans_equipe.png"
        case .inbox: "tbfc/icons/icones_ecrans_messages.png"
        case .usage: "tbfc/icons/icones_ecrans_classement.png"
        case .rules: "tbfc/icons/icones_ecrans_quetes.png"
        case .stats: "tbfc/icons/icones_ecrans_succes.png"
        case .domain: "tbfc/icons/icones_ecrans_carte.png"
        case .settings: "tbfc/icons/icones_ecrans_parametres.png"
        case .close: "tbfc/icons/icones_actions_retour.png"
        }
    }
}

@MainActor
final class GameModel: ObservableObject, WorldSceneDelegate {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var usage: UsageReport?
    @Published private(set) var rules: [RuleItem] = []
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var analytics: AnalyticsReport?
    @Published private(set) var insightsReady = false
    @Published private(set) var room: RoomID = .office
    @Published var panel: Panel?
    @Published var dialog: Dialog?
    @Published var dialogPage = 0
    @Published var dialogChoice = 0
    @Published var menuOpen = false
    @Published var menuIndex = 0
    @Published var toast: String?
    @Published var settings: Settings

    let scene: WorldScene
    let monitor = AgentMonitor()
    let historyMonitor = AgentMonitor(keepMessages: false)
    private let historyWorker = DispatchQueue(label: "boss.history", qos: .utility)
    let store = Store()
    let engine = SuggestionEngine()
    lazy var usageService = UsageService(monitor: historyMonitor, liveMonitor: monitor)
    private let worker = DispatchQueue(label: "boss.scan", qos: .utility)
    private var timers: [Timer] = []
    private var previousStatus: [String: AgentStatus] = [:]
    private var insightsRunning = false
    private var toastTask: Task<Void, Never>?

    struct Settings: Codable, Equatable {
        var notifications = true
        var sounds = true
        var zoom: Double = 1.5
        var finishedHours: Double = 6
        var autoRefine = false

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            notifications = try container.decodeIfPresent(Bool.self, forKey: .notifications) ?? true
            sounds = try container.decodeIfPresent(Bool.self, forKey: .sounds) ?? true
            zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1.5
            finishedHours = try container.decodeIfPresent(Double.self, forKey: .finishedHours) ?? 6
            autoRefine = try container.decodeIfPresent(Bool.self, forKey: .autoRefine) ?? false
        }
    }

    @Published var refining: Set<String> = []
    @Published var repairingClaude = false

    func openClaudeLogin() {
        let script = Paths.appSupport.appendingPathComponent("claude-login.command")
        let claude = RuleWriter.claudeExecutable() ?? "claude"
        let body = "#!/bin/sh\n\(SessionLauncher.shellQuote(claude)) auth login\necho\necho \"Tu peux fermer cette fenêtre et revenir dans The Boss.\"\n"
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            showToast("Impossible d'ouvrir le Terminal : \(error.localizedDescription)")
        }
    }

    func repairClaudeUsage() {
        guard !repairingClaude else { return }
        repairingClaude = true
        Task {
            let ok = await RuleWriter.refreshClaudeLogin()
            self.usageService.forgetClaudeCredentials()
            self.repairingClaude = false
            self.showToast(ok ? "Jeton Claude rafraîchi" : "Claude Code n'a pas pu se reconnecter : lance `claude auth login`")
            self.refreshUsage(force: true)
        }
    }

    func refine(_ suggestion: Suggestion) {
        guard !refining.contains(suggestion.id) else { return }
        refining.insert(suggestion.id)
        Task {
            let result = await RuleWriter.refine(suggestion)
            self.refining.remove(suggestion.id)
            switch result {
            case .success(let rule?):
                guard let index = self.suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
                self.suggestions[index].refine(with: rule)
                self.store.save(self.suggestions[index])
                self.showToast("Règle reformulée par Claude")
            case .success(nil):
                self.showToast("Claude ne voit pas de règle générale ici")
            case .failure(let error):
                self.showToast(error.localizedDescription)
            }
        }
    }

    init() {
        let stored = Store().setting("settings").flatMap { try? JSONDecoder().decode(Settings.self, from: Data($0.utf8)) }
        settings = stored ?? Settings()
        scene = WorldScene(size: CGSize(width: 1280, height: 800))
        scene.controller = self
        scene.setZoom(settings.zoom)
    }

    var isInputBlocked: Bool { panel != nil || dialog != nil || menuOpen }

    var needsYou: [AgentSession] { sessions.filter { $0.status == .needsApproval } }
    var working: [AgentSession] { sessions.filter { $0.status == .working } }
    var finished: [AgentSession] { sessions.filter { $0.status == .finished } }
    var openSuggestions: [Suggestion] { suggestions.filter { $0.status == .new } }

    func start() {
        refreshSessions()
        refreshUsage(force: true)
        refreshInsights()
        timers = [
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshSessions() } },
            Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshUsage(force: false) } },
            Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshInsights() } },
        ]
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings), let text = String(data: data, encoding: .utf8) {
            store.setSetting("settings", text)
        }
        scene.setZoom(settings.zoom)
        applyFloor()
    }

    func refreshSessions() {
        let monitor = monitor
        worker.async {
            let sessions = monitor.sessions()
            DispatchQueue.main.async { [weak self] in self?.apply(sessions) }
        }
    }

    private func apply(_ sessions: [AgentSession]) {
        var newlyWaiting: [AgentSession] = []
        var newlyDone: [AgentSession] = []
        for session in sessions {
            let previous = previousStatus[session.id]
            if previous != nil && previous != session.status {
                if session.status == .needsApproval { newlyWaiting.append(session) }
                if session.status == .finished && previous == .working { newlyDone.append(session) }
            }
            previousStatus[session.id] = session.status
        }
        self.sessions = sessions
        applyFloor()
        NSApp.dockTile.badgeLabel = needsYou.isEmpty ? nil : "\(needsYou.count)"
        for session in newlyWaiting {
            notify(title: "\(session.harness.displayName) attend ton feu vert", body: session.title, sound: "Glass")
            showToast("⚠ \(session.projectName) : un robot attend ton feu vert")
        }
        for session in newlyDone {
            notify(title: "\(session.harness.displayName) a fini", body: session.title, sound: "Tink")
        }
    }

    var floorSessions: [AgentSession] {
        let cutoff = Date().addingTimeInterval(-settings.finishedHours * 3600)
        return Array(sessions.filter { $0.status != .finished || $0.isLive || $0.updatedAt > cutoff }.prefix(Room.openSpace.desks.count))
    }

    private func applyFloor() {
        scene.setFloor(floorSessions)
        scene.setInbox(count: openSuggestions.count)
    }

    func refreshUsage(force: Bool) {
        let service = usageService
        let store = store
        Task {
            if self.usage == nil {
                let codex = await Task.detached { service.codexUsage() }.value
                if self.usage == nil { self.usage = UsageReport(providers: [codex], daily: []) }
            }
            let report = await service.report(force: force)
            store.recordUsage(report.providers)
            self.usage = report
            if self.insightsReady { self.analytics = Analytics.build(store: store, daily: report.daily) }
        }
    }

    func refreshInsights() {
        guard !insightsRunning else { return }
        insightsRunning = true
        let monitor = historyMonitor, store = store, engine = engine
        let currentSessions = sessions
        historyWorker.async {
            let prompts = monitor.prompts(within: 30 * 86400)
            store.record(prompts: prompts)
            let fresh = engine.suggestions(prompts: prompts, sessions: currentSessions.isEmpty ? monitor.sessions() : currentSessions)
            let saved = store.savedSuggestions()
            let rules = RulesInventory().scan(projects: (currentSessions.isEmpty ? monitor.sessions() : currentSessions).map(\.cwd))
            let daily = monitor.dailyTokens(within: 30 * 86400)
            let analytics = Analytics.build(store: store, daily: daily)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let savedById = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                var merged = fresh.map { suggestion -> Suggestion in
                    var copy = suggestion
                    if let saved = savedById[suggestion.id] {
                        copy.status = saved.status
                        if let refined = saved.refinedRule { copy.refine(with: refined) }
                    }
                    return copy
                }
                let freshIds = Set(fresh.map(\.id))
                merged += saved.filter { !freshIds.contains($0.id) && $0.status != .new }
                let before = Set(self.openSuggestions.map(\.id))
                self.suggestions = merged.sorted { $0.createdAt > $1.createdAt }
                self.rules = rules
                self.analytics = analytics
                let added = self.openSuggestions.filter { !before.contains($0.id) }
                if self.insightsReady && !added.isEmpty {
                    self.notify(title: "Nouveau courrier", body: added[0].title, sound: "Pop")
                }
                self.insightsReady = true
                self.insightsRunning = false
                self.applyFloor()
                if self.settings.autoRefine {
                    for suggestion in self.openSuggestions where suggestion.kind == .learnedRule && suggestion.refinedRule == nil {
                        self.refine(suggestion)
                    }
                }
            }
        }
    }

    func setStatus(_ status: SuggestionStatus, for suggestion: Suggestion) {
        var copy = suggestion
        if status == .applied {
            do {
                try suggestion.apply()
            } catch {
                showToast("Impossible d'écrire \(suggestion.displayPath) : \(error.localizedDescription)")
                return
            }
        }
        copy.status = status
        store.save(copy)
        if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) { suggestions[index] = copy }
        applyFloor()
        switch status {
        case .applied: showToast("Règle écrite dans \(suggestion.displayPath)"); play("Glass")
        case .saved: showToast("Gardée pour plus tard")
        case .dismissed: showToast("Suggestion ignorée")
        case .new: break
        }
    }

    var domainProjects: [String] { DomainModelBuilder.projects(from: sessions) }

    func domainModel(root: String) -> DomainModel {
        DomainModelBuilder.build(root: root, intent: store.setting("intent:\(root)") ?? "", sessions: sessions, suggestions: suggestions)
    }

    func saveIntent(_ intent: String, root: String) {
        store.setSetting("intent:\(root)", intent)
    }

    func exportDomain(_ model: DomainModel) {
        let url = URL(fileURLWithPath: model.exportPath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try model.markdown.write(to: url, atomically: true, encoding: .utf8)
            showToast("Modèle écrit dans \(model.name)/.boss/domain.md")
            play("Glass")
        } catch {
            showToast("Écriture impossible : \(error.localizedDescription)")
        }
    }

    func messages(for session: AgentSession) -> [TranscriptMessage] {
        monitor.messages(for: session)
    }

    func session(id: String) -> AgentSession? { sessions.first { $0.id == id } }

    func world(didEnter room: RoomID) {
        self.room = room
    }

    func worldDidRequestMenu() {
        play("Tink")
        menuIndex = 0
        menuOpen = true
    }

    func world(didInteract interaction: Interaction, session: AgentSession?) {
        play("Tink")
        switch interaction {
        case .usage: open(.usage)
        case .library: open(.library)
        case .analytics: open(.analytics)
        case .overview: open(.overview)
        case .archives: open(.domain)
        case .inbox:
            if !insightsReady {
                say(nil, ["Le facteur trie encore le courrier… (analyse de tes conversations en cours)"])
            } else if openSuggestions.isEmpty && !suggestions.contains(where: { $0.status == .saved }) {
                say(nil, ["La bannette est vide.", "Tes agents n'ont rien appris de nouveau cette semaine. Corrige-les et le courrier arrivera."],
                    choices: [DialogChoice(title: "Voir l'historique") { [weak self] in self?.open(.inbox) }, DialogChoice(title: "Fermer") {}])
            } else {
                open(.inbox)
            }
        case .robot:
            if let session { talk(to: session) } else {
                say(nil, ["Un bureau libre.", "Lance un agent (Claude Code, Codex, Cursor, Pi…) et un robot viendra s'installer ici."])
            }
        case .coffee:
            let today = usage?.today.total ?? 0
            say(nil, ["La machine crache un expresso brûlant.", "Pendant ce temps, tes robots ont avalé \(formatTokens(today)) tokens aujourd'hui."])
        case .water:
            say(nil, ["Glou glou.", "Les robots ne boivent pas d'eau. Ils préfèrent le contexte frais."])
        case .sofa:
            say(nil, ["Tu t'affales dans le canapé.", working.isEmpty ? "Personne ne bosse. Profite." : "\(working.count) robot\(working.count > 1 ? "s" : "") bosse\(working.count > 1 ? "nt" : "") pour toi. Profite."])
        case .servers:
            let installed = monitor.installedHarnesses().map(\.displayName).joined(separator: ", ")
            say(nil, ["Les baies ronronnent.", "Harnais détectés sur ce Mac : \(installed.isEmpty ? "aucun" : installed).",
                      "Tout reste ici : tes conversations sont lues en local et rangées dans une base SQLite sur ton Mac."])
        case .window:
            say(nil, ["Il fait beau dehors.", "Tes robots ne voient jamais le soleil. C'est pour ça qu'ils bossent bien."])
        case .plant:
            say(nil, ["Une plante verte.", "Elle a l'air d'aller mieux que ta fenêtre de contexte."])
        }
    }

    func talk(to session: AgentSession) {
        var pages: [String] = []
        let project = session.projectName.isEmpty ? "un projet" : session.projectName
        switch session.status {
        case .working:
            pages.append("Je bosse sur « \(session.title) » dans \(project).")
            if let prompt = session.lastPrompt { pages.append("Ton dernier ordre : « \(prompt.singleLineTruncated(180)) »") }
        case .needsApproval:
            pages.append("Boss ! J'ai besoin de ton feu vert dans \(project).")
            if let pending = session.pendingAction { pages.append("Je veux lancer : \(pending.singleLineTruncated(180))") }
            pages.append("Valide-moi dans \(session.harness.displayName) et je repars.")
        case .finished:
            pages.append("J'ai fini « \(session.title) » dans \(project).")
            if let reply = session.lastReply { pages.append("Mon dernier mot : « \(reply.singleLineTruncated(200)) »") }
        }
        var choices: [DialogChoice] = [
            DialogChoice(title: "Lire le journal") { [weak self] in self?.open(.robot(session.id)) },
            DialogChoice(title: "Aller à la session") { [weak self] in self?.focus(session) },
        ]
        if !session.cwd.isEmpty {
            choices.append(DialogChoice(title: "Ouvrir le dossier") { NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd)) })
        }
        choices.append(DialogChoice(title: "Rien, continue") {})
        say("\(RobotName.of(session))", pages, portrait: Theme.robotImage(for: session.harness), choices: choices)
    }

    func focus(_ session: AgentSession) {
        if SessionLauncher.focus(session) {
            showToast("Session ouverte")
        } else {
            let command = SessionLauncher.resumeCommand(session)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            showToast("Commande copiée : \(command)")
        }
    }

    func say(_ speaker: String?, _ pages: [String], portrait: NSImage? = nil, choices: [DialogChoice] = []) {
        menuOpen = false
        dialogPage = 0
        dialogChoice = 0
        dialog = Dialog(speaker: speaker, portrait: portrait, pages: pages, choices: choices)
    }

    func open(_ panel: Panel) {
        menuOpen = false
        dialog = nil
        self.panel = panel
        play("Pop")
    }

    func closePanel() {
        panel = nil
        scene.endConversation()
        play("Tink")
    }

    func closeDialog() {
        dialog = nil
        scene.endConversation()
    }

    func advanceDialog() {
        guard let dialog else { return }
        if dialogPage < dialog.pages.count - 1 {
            dialogPage += 1
            play("Tink")
            return
        }
        let choice = dialog.choices.indices.contains(dialogChoice) ? dialog.choices[dialogChoice] : nil
        closeDialog()
        choice?.action()
    }

    func moveDialogChoice(_ delta: Int) {
        guard let dialog, !dialog.choices.isEmpty, dialogPage == dialog.pages.count - 1 else { return }
        dialogChoice = (dialogChoice + delta + dialog.choices.count) % dialog.choices.count
        play("Tink")
    }

    func moveMenu(_ delta: Int) {
        menuIndex = (menuIndex + delta + MenuEntry.allCases.count) % MenuEntry.allCases.count
        play("Tink")
    }

    func select(_ entry: MenuEntry) {
        menuOpen = false
        switch entry {
        case .agents: open(.overview)
        case .inbox: open(.inbox)
        case .usage: open(.usage)
        case .rules: open(.library)
        case .stats: open(.analytics)
        case .domain: open(.domain)
        case .settings: open(.settings)
        case .close: play("Tink")
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        if panel != nil {
            if event.keyCode == 53 { closePanel(); return true }
            return false
        }
        if dialog != nil {
            switch event.keyCode {
            case 49, 36, 14, 6, 76: advanceDialog()
            case 126, 13: moveDialogChoice(-1)
            case 125, 1: moveDialogChoice(1)
            case 53, 7: closeDialog()
            default: break
            }
            return true
        }
        if menuOpen {
            switch event.keyCode {
            case 126, 13: moveMenu(-1)
            case 125, 1: moveMenu(1)
            case 49, 36, 14, 6, 76: select(MenuEntry.allCases[menuIndex])
            case 53, 48, 7: menuOpen = false
            default: break
            }
            return true
        }
        return scene.handleKeyDown(event)
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func play(_ name: String) {
        guard settings.sounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func notify(title: String, body: String, sound: String) {
        play(sound)
        guard settings.notifications, Bundle.main.bundleIdentifier != nil, !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

enum RobotName {
    static func of(_ session: AgentSession) -> String {
        let prefix: String
        switch session.harness {
        case .claude: prefix = "CLAUDE"
        case .codex: prefix = "CODEX"
        case .cursor: prefix = "CURSOR"
        case .pi: prefix = "PI"
        case .omp: prefix = "OMP"
        }
        return "\(prefix)-\(stableNumber(session.sessionId))"
    }

    static func stableNumber(_ id: String) -> Int {
        var hash: UInt32 = 2166136261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return Int(hash % 900) + 100
    }
}

extension String {
    func singleLineTruncated(_ limit: Int) -> String {
        let line = split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }
}
