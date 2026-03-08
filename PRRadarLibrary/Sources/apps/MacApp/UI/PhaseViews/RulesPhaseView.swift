import PRRadarModels
import SwiftUI

struct RulesPhaseView: View {

    let focusAreas: [FocusArea]
    let rules: [ReviewRule]
    let tasks: [RuleRequest]

    var body: some View {
        VStack(spacing: 0) {
            PhaseSummaryBar(items: [
                .init(label: "Focus areas:", value: "\(focusAreas.count)"),
                .init(label: "Available Rules:", value: "\(rules.count)"),
                .init(label: "Evaluation Tasks:", value: "\(tasks.count)"),
            ])
            .padding(8)

            List {
                focusAreasSection
                rulesSection
                tasksSection
            }
        }
    }

    // MARK: - Focus Areas

    private var fileGroups: [FileGroup] {
        FileGroup.fromFocusAreas(focusAreas)
    }

    @ViewBuilder
    private var focusAreasSection: some View {
        Section("Focus Areas") {
            ForEach(fileGroups) { group in
                DisclosureGroup(group.filePath) {
                    ForEach(group.areas) { area in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(area.description)
                                .font(.body)
                            HStack {
                                Text("Lines \(area.startLine)-\(area.endLine)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(area.focusType.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.quaternary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rules

    @ViewBuilder
    private var rulesSection: some View {
        Section("Available Rules") {
            ForEach(rules) { rule in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(rule.content)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        if let link = rule.documentationLink {
                            HStack(spacing: 4) {
                                Text("Docs:")
                                    .foregroundStyle(.secondary)
                                Text(link)
                                    .foregroundStyle(.blue)
                            }
                            .font(.caption)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rule.displayName)
                                .font(.headline)
                            Spacer()
                            Text(rule.category)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }

                        Text(rule.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Tasks

    private var taskGroups: [RuleGroup] {
        RuleGroup.fromTasks(tasks)
    }

    @ViewBuilder
    private var tasksSection: some View {
        Section("Evaluation Tasks") {
            ForEach(taskGroups) { group in
                DisclosureGroup {
                    ForEach(group.tasks) { task in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.focusArea.description)
                                .font(.body)
                            HStack {
                                Text(task.focusArea.filePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Lines \(task.focusArea.startLine)-\(task.focusArea.endLine)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(group.displayName)
                            .font(.body)
                        Spacer()
                        Text("\(group.tasks.count) tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Grouping

private struct FileGroup: Identifiable {
    let filePath: String
    let areas: [FocusArea]

    var id: String { filePath }

    static func fromFocusAreas(_ areas: [FocusArea]) -> [FileGroup] {
        var grouped: [String: [FocusArea]] = [:]
        var order: [String] = []
        for area in areas {
            if grouped[area.filePath] == nil {
                order.append(area.filePath)
            }
            grouped[area.filePath, default: []].append(area)
        }
        return order.map { FileGroup(filePath: $0, areas: grouped[$0]!) }
    }
}
