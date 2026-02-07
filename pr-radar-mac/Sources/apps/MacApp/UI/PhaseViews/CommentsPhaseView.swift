import PRRadarModels
import SwiftUI

struct CommentsPhaseView: View {

    let evaluations: [RuleEvaluationResult]
    let cliOutput: String?
    let posted: Bool
    var onPost: ((_ dryRun: Bool) -> Void)?

    @State private var selectedIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            commentsList
        }
        .onAppear {
            selectedIds = Set(violations.map(\.taskId))
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack {
            PhaseSummaryBar(items: [
                .init(label: "Comments:", value: "\(violations.count)"),
                .init(label: "Selected:", value: "\(selectedIds.count)"),
            ])

            Spacer()

            if !posted {
                Button("Select All") {
                    selectedIds = Set(violations.map(\.taskId))
                }

                Button("Deselect All") {
                    selectedIds.removeAll()
                }

                Button("Post Selected") {
                    onPost?(false)
                }
                .disabled(selectedIds.isEmpty)
                .buttonStyle(.borderedProminent)
            } else {
                Text("Comments posted")
                    .foregroundStyle(.green)
                    .bold()
            }
        }
        .padding()
    }

    // MARK: - Comments List

    @ViewBuilder
    private var commentsList: some View {
        if violations.isEmpty {
            ContentUnavailableView(
                "No Violations",
                systemImage: "checkmark.circle",
                description: Text("No violations to comment on.")
            )
        } else {
            List {
                ForEach(violations, id: \.taskId) { result in
                    commentRow(result)
                }

                if let output = cliOutput, !output.isEmpty {
                    Section("CLI Output") {
                        Text(output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ result: RuleEvaluationResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !posted {
                Toggle("", isOn: Binding(
                    get: { selectedIds.contains(result.taskId) },
                    set: { isOn in
                        if isOn {
                            selectedIds.insert(result.taskId)
                        } else {
                            selectedIds.remove(result.taskId)
                        }
                    }
                ))
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SeverityBadge(score: result.evaluation.score)

                    Text(result.ruleName)
                        .font(.headline)

                    Spacer()

                    Text(fileLocation(result))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(result.evaluation.comment)
                    .font(.body)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var violations: [RuleEvaluationResult] {
        evaluations.filter(\.evaluation.violatesRule)
    }

    private func fileLocation(_ result: RuleEvaluationResult) -> String {
        if let line = result.evaluation.lineNumber {
            return "\(result.filePath):\(line)"
        }
        return result.filePath
    }
}
