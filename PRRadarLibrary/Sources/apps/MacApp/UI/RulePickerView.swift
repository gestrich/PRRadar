import SwiftUI
import PRRadarModels
import PRRadarConfigService

struct RulePickerView: View {

    let ruleSets: [RuleSetGroup]
    let initialSelectedFilePaths: Set<String>?
    let onStart: ([ReviewRule]) -> Void
    let onCancel: () -> Void

    @State private var selectedFilePaths: Set<String>

    init(
        ruleSets: [RuleSetGroup],
        initialSelectedFilePaths: Set<String>? = nil,
        onStart: @escaping ([ReviewRule]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.ruleSets = ruleSets
        self.initialSelectedFilePaths = initialSelectedFilePaths
        self.onStart = onStart
        self.onCancel = onCancel

        let allPaths = Set(ruleSets.flatMap(\.rules).map(\.filePath))
        if let saved = initialSelectedFilePaths {
            let valid = saved.intersection(allPaths)
            self._selectedFilePaths = State(initialValue: valid.isEmpty ? allPaths : valid)
        } else {
            self._selectedFilePaths = State(initialValue: allPaths)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ruleList
            Divider()
            footer
        }
        .frame(width: 360)
        .frame(minHeight: 300, idealHeight: 420, maxHeight: 600)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Select Rules")
                .font(.headline)
            Spacer()
            Button("All") { selectAll() }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            Text("/")
                .foregroundStyle(.secondary)
            Button("None") { selectedFilePaths.removeAll() }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
        }
        .padding()
    }

    // MARK: - Rule List

    private var ruleList: some View {
        List {
            ForEach(ruleSets) { ruleSet in
                Section {
                    ForEach(ruleSet.rules, id: \.filePath) { rule in
                        ruleRow(rule)
                    }
                } header: {
                    ruleSetHeader(ruleSet)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func ruleSetHeader(_ ruleSet: RuleSetGroup) -> some View {
        let allSelected = ruleSet.rules.allSatisfy { selectedFilePaths.contains($0.filePath) }
        let noneSelected = ruleSet.rules.allSatisfy { !selectedFilePaths.contains($0.filePath) }
        let selectedCount = ruleSet.rules.filter { selectedFilePaths.contains($0.filePath) }.count

        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { allSelected },
                set: { newValue in
                    for rule in ruleSet.rules {
                        if newValue {
                            selectedFilePaths.insert(rule.filePath)
                        } else {
                            selectedFilePaths.remove(rule.filePath)
                        }
                    }
                }
            )) {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(ruleSet.name.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.5)
                }
            }
            .toggleStyle(.checkbox)
            .if(!allSelected && !noneSelected) { view in
                view.foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(selectedCount)/\(ruleSet.rules.count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func ruleRow(_ rule: ReviewRule) -> some View {
        Toggle(isOn: Binding(
            get: { selectedFilePaths.contains(rule.filePath) },
            set: { newValue in
                if newValue {
                    selectedFilePaths.insert(rule.filePath)
                } else {
                    selectedFilePaths.remove(rule.filePath)
                }
            }
        )) {
            HStack {
                Text(rule.name)
                    .lineLimit(1)
                Spacer()
                analysisTypeBadge(rule.analysisType)
            }
        }
        .toggleStyle(.checkbox)
    }

    private func analysisTypeBadge(_ type: RuleAnalysisType) -> some View {
        Text(type.rawValue.uppercased())
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(badgeColor(for: type).opacity(0.15))
            .foregroundStyle(badgeColor(for: type))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func badgeColor(for type: RuleAnalysisType) -> Color {
        switch type {
        case .ai: .purple
        case .regex: .orange
        case .script: .blue
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(selectedFilePaths.count) of \(allRules.count) rules")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button("Start") {
                let selected = allRules.filter { selectedFilePaths.contains($0.filePath) }
                onStart(selected)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedFilePaths.isEmpty)
        }
        .padding()
    }

    // MARK: - Helpers

    private var allRules: [ReviewRule] {
        ruleSets.flatMap(\.rules)
    }

    private func selectAll() {
        selectedFilePaths = Set(allRules.map(\.filePath))
    }
}

// MARK: - RuleSetGroup

struct RuleSetGroup: Identifiable {
    let id: UUID
    let name: String
    let rules: [ReviewRule]

    init(name: String, rules: [ReviewRule]) {
        self.id = UUID()
        self.name = name
        self.rules = rules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    init(rulePath: RulePath, rules: [ReviewRule]) {
        self.init(name: rulePath.name, rules: rules)
    }
}

// MARK: - Conditional Modifier

private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
