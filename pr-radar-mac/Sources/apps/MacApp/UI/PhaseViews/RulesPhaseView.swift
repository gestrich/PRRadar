import PRRadarModels
import SwiftUI

struct RulesPhaseView: View {

    private struct SectionID: Hashable {
        let section: String
        let value: String
    }

    let focusAreas: [FocusArea]
    let rules: [ReviewRule]
    let tasks: [EvaluationTaskOutput]

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

    @ViewBuilder
    private var focusAreasSection: some View {
        Section("Focus Areas") {
            let grouped = Dictionary(grouping: focusAreas, by: \.filePath)
            ForEach(grouped.keys.sorted(), id: \.self) { file in
                DisclosureGroup(file) {
                    ForEach(grouped[file]!, id: \.focusId) { area in
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
            ForEach(rules, id: \.name) { rule in
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
                            Text(rule.name)
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

    @ViewBuilder
    private var tasksSection: some View {
        Section("Evaluation Tasks") {
            let grouped = Dictionary(grouping: tasks, by: \.rule.name)
            let taskGroupIds = grouped.keys.sorted().map { SectionID(section: "tasks", value: $0) }
            ForEach(taskGroupIds, id: \.self) { groupId in
                DisclosureGroup {
                    ForEach(grouped[groupId.value]!, id: \.taskId) { task in
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
                        Text(groupId.value)
                            .font(.body)
                        Spacer()
                        Text("\(grouped[groupId.value]!.count) tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
