import BossCore
import SwiftUI

struct DomainPanel: View {
    @ObservedObject var model: GameModel
    @State private var selected: String?
    @State private var intent = ""
    @State private var domain: DomainModel?
    @State private var showExport = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Projets")
                Text("Une source de vérité par projet : ce que tu veux, les conventions écrites, les décisions apprises, le travail en cours.")
                    .font(Theme.body(12)).foregroundStyle(Theme.ink.opacity(0.65))
                if model.domainProjects.isEmpty {
                    EmptyState(text: "Aucun projet : lance un agent dans un dépôt.")
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.domainProjects, id: \.self) { root in
                            let count = model.sessions.filter { RulesInventory.projectRoot($0.cwd) == root }.count
                            HStack {
                                PixelImage(image: Assets.image("tbfc/icons/icones_ecrans_carte.png"), size: 22)
                                Text((root as NSString).lastPathComponent).font(Theme.body(13, weight: .semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(count)").font(Theme.pixel(13)).foregroundStyle(Theme.ink.opacity(0.6))
                            }
                            .padding(8)
                            .background(root == selected ? Theme.crust.opacity(0.35) : Theme.paper.opacity(0.5))
                            .overlay(Rectangle().stroke(Theme.ink, lineWidth: root == selected ? 3 : 2))
                            .contentShape(Rectangle())
                            .onTapGesture { select(root) }
                        }
                    }
                    .padding(2)
                }
            }
            .padding(18)
            .frame(width: 300)
            Rectangle().fill(Theme.ink).frame(width: 3)
            if let domain {
                detail(domain)
            } else {
                EmptyState(text: "Choisis un projet.")
            }
        }
        .onAppear { if selected == nil, let first = model.domainProjects.first { select(first) } }
    }

    func select(_ root: String) {
        if let selected { model.saveIntent(intent, root: selected) }
        selected = root
        let built = model.domainModel(root: root)
        domain = built
        intent = built.intent
        showExport = false
    }

    func detail(_ domain: DomainModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(domain.name).font(Theme.pixel(22)).foregroundStyle(Theme.ink)
                        Text(domain.root.replacingOccurrences(of: Paths.home.path, with: "~")).font(Theme.mono(11)).foregroundStyle(Theme.ink.opacity(0.6))
                    }
                    Spacer()
                    ForEach(domain.agents.sorted { $0.value > $1.value }, id: \.key) { harness, count in
                        Text("\(harness.displayName) \(count)").font(Theme.pixel(12)).foregroundStyle(Theme.cream)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.color(for: harness))
                    }
                }
                SectionTitle(text: "Intention du projet")
                TextEditor(text: $intent)
                    .font(Theme.body(13))
                    .frame(minHeight: 70)
                    .padding(6)
                    .background(Color.white.opacity(0.8))
                    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
                    .onChange(of: intent) { model.saveIntent(intent, root: domain.root) }
                Text("Ce que le projet doit accomplir, pour qui, et ce qui compte plus que tout. Tes agents le liront si tu exportes le modèle.")
                    .font(Theme.body(11)).foregroundStyle(Theme.ink.opacity(0.55))
                ForEach(domain.conflicts, id: \.self) { conflict in
                    Text("⚠ " + conflict).font(Theme.body(12, weight: .semibold)).foregroundStyle(Theme.warning)
                }
                factSection("Conventions écrites", domain.conventions, empty: "Aucune règle écrite pour ce projet.")
                factSection("Décisions apprises", domain.decisions, empty: "Pas encore de règle apprise.")
                factSection("Travaux récents", Array(domain.activity.prefix(12)), empty: "Pas de session récente.")
                HStack {
                    PixelButton(title: showExport ? "Masquer l'aperçu" : "Exporter pour les agents", color: Theme.paper) { showExport.toggle() }
                    Spacer()
                }
                if showExport {
                    let exported = withIntent(domain)
                    SectionTitle(text: "Diff exact · \(domain.name)/.boss/domain.md")
                    DiffView(lines: UnifiedDiff.lines(old: (try? String(contentsOfFile: exported.exportPath, encoding: .utf8)) ?? "",
                                                      new: exported.markdown, path: ".boss/domain.md"))
                    PixelButton(title: "Écrire le fichier", color: Theme.success) { model.exportDomain(exported) }
                }
            }
            .padding(18)
        }
    }

    func withIntent(_ domain: DomainModel) -> DomainModel {
        var copy = domain
        copy.intent = intent
        return copy
    }

    func factSection(_ title: String, _ facts: [DomainFact], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "\(title) · \(facts.count)")
            if facts.isEmpty {
                Text(empty).font(Theme.body(12)).foregroundStyle(Theme.ink.opacity(0.55))
            }
            ForEach(facts.prefix(40)) { fact in
                HStack(alignment: .top, spacing: 8) {
                    Text("▸").font(Theme.pixel(12)).foregroundStyle(Theme.pink)
                    Text(fact.text).font(Theme.body(12)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(fact.source).font(Theme.pixel(11)).foregroundStyle(Theme.ink.opacity(0.5))
                }
            }
        }
    }
}
