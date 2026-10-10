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
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("One source of truth per project: what you want, the written conventions, the learned decisions, the work in progress."))
                    .font(Theme.body(13)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                if model.domainProjects.isEmpty {
                    EmptyState(text: tr("No project yet: start an agent inside a repository."))
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.domainProjects, id: \.self) { root in
                            projectRow(root)
                        }
                    }
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                }
            }
            .padding(20)
            .frame(width: 300)
            Rectangle().fill(Theme.ink).frame(width: 3)
            if let domain {
                detail(domain)
            } else {
                EmptyState(text: tr("Pick a project."))
            }
        }
        .onAppear { if selected == nil, let first = model.domainProjects.first { select(first) } }
    }

    func projectRow(_ root: String) -> some View {
        let count = model.sessions.filter { RulesInventory.projectRoot($0.cwd) == root }.count
        let isSelected = root == selected
        return HStack(spacing: 10) {
            PixelImage(image: Icon.domain, size: 22)
            Text((root as NSString).lastPathComponent).font(Theme.label(14, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer()
            Text(count == 1 ? tr("1 session") : tr("%d sessions", count)).font(Theme.label(11, .heavy)).foregroundStyle(Theme.inkSoft)
        }
        .padding(10)
        .card(fill: isSelected ? Color(hex: 0xFFF1C9) : Theme.card, border: isSelected ? Theme.crustDark : Theme.ink, lift: isSelected ? 0 : 2)
        .contentShape(Rectangle())
        .onTapGesture { select(root) }
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
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(domain.name).font(Theme.title(24)).foregroundStyle(Theme.ink)
                        Text(domain.root.replacingOccurrences(of: Paths.home.path, with: "~")).font(Theme.mono(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    ForEach(domain.agents.sorted { $0.value > $1.value }, id: \.key) { harness, count in
                        HStack(spacing: 4) {
                            HarnessTag(harness: harness)
                            Text("× \(count)").font(Theme.label(12, .bold)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: tr("Project intent"))
                    TextEditor(text: $intent)
                        .font(Theme.body(14))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80)
                        .padding(8)
                        .card(lift: 0)
                        .onChange(of: intent) { model.saveIntent(intent, root: domain.root) }
                    Text(tr("What the project must achieve, for whom, and what matters most. Your agents will read it if you export the model."))
                        .font(Theme.label(12, .medium)).foregroundStyle(Theme.inkSoft)
                }
                ForEach(domain.conflicts, id: \.self) { conflict in
                    Text(conflict).font(Theme.label(13, .bold)).foregroundStyle(Theme.ink)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warning.opacity(0.2))
                        .overlay(Rectangle().stroke(Theme.warning, lineWidth: 2))
                }
                factSection(tr("Written conventions"), domain.conventions, empty: tr("No written rule for this project."))
                factSection(tr("Learned decisions"), domain.decisions, empty: tr("No learned rule yet."))
                factSection(tr("Recent work"), Array(domain.activity.prefix(12)), empty: tr("No recent session."))
                HStack {
                    PixelButton(title: showExport ? tr("Hide preview") : tr("Export for the agents"), color: Theme.card) { showExport.toggle() }
                    Spacer()
                }
                if showExport {
                    let exported = withIntent(domain)
                    SectionTitle(text: tr("Exact diff · %@", "\(domain.name)/.boss/domain.md"))
                    DiffView(lines: UnifiedDiff.lines(old: (try? String(contentsOfFile: exported.exportPath, encoding: .utf8)) ?? "",
                                                      new: exported.markdown, path: ".boss/domain.md"))
                    PixelButton(title: tr("Write the file"), color: Theme.success) { model.exportDomain(exported) }
                }
            }
            .padding(22)
        }
    }

    func withIntent(_ domain: DomainModel) -> DomainModel {
        var copy = domain
        copy.intent = intent
        return copy
    }

    func factSection(_ title: String, _ facts: [DomainFact], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: title)
                Text("\(facts.count)").font(Theme.label(11, .heavy)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.ink.opacity(0.07))
            }
            VStack(alignment: .leading, spacing: 0) {
                if facts.isEmpty {
                    Text(empty).font(Theme.body(13)).foregroundStyle(Theme.inkSoft).padding(12)
                }
                ForEach(Array(facts.prefix(40).enumerated()), id: \.element.id) { index, fact in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("▸").font(Theme.label(12, .bold)).foregroundStyle(Theme.pink)
                        Text(fact.text).font(Theme.body(14)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 10)
                        Text(fact.source).font(Theme.label(11, .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(index % 2 == 0 ? Color.clear : Theme.ink.opacity(0.03))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}
