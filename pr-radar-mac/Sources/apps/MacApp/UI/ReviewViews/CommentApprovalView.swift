import AppKit
import PRRadarModels
import SwiftUI

struct CommentApprovalView: View {

    let evaluations: [RuleEvaluationResult]
    let posted: Bool
    var onPost: ((_ dryRun: Bool) -> Void)?

    @Environment(ReviewModel.self) private var reviewModel
    @State private var approvedIds: Set<String> = []
    @State private var selectedViolation: RuleEvaluationResult?
    @State private var editedComments: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                violationsList
                    .frame(minWidth: 280, idealWidth: 320)
                detailPanel
            }
        }
        .onAppear {
            approvedIds = Set(violations.map(\.taskId))
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack {
            Text("\(approvedIds.count) of \(violations.count) comments approved")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if !posted {
                Button("Select All") {
                    approvedIds = Set(violations.map(\.taskId))
                }

                Button("Deselect All") {
                    approvedIds.removeAll()
                }

                Button("Post Approved (\(approvedIds.count))") {
                    onPost?(false)
                }
                .disabled(approvedIds.isEmpty)
                .buttonStyle(.borderedProminent)
            } else {
                Label("Comments posted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .bold()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Violations List

    @ViewBuilder
    private var violationsList: some View {
        if violations.isEmpty {
            ContentUnavailableView(
                "No Violations",
                systemImage: "checkmark.circle",
                description: Text("No rule violations were found.")
            )
        } else {
            List(selection: Binding(
                get: { selectedViolation?.taskId },
                set: { id in selectedViolation = violations.first { $0.taskId == id } }
            )) {
                ForEach(violations, id: \.taskId) { result in
                    violationRow(result)
                        .tag(result.taskId)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func violationRow(_ result: RuleEvaluationResult) -> some View {
        HStack(spacing: 8) {
            if !posted {
                Toggle("", isOn: Binding(
                    get: { approvedIds.contains(result.taskId) },
                    set: { isOn in
                        if isOn { approvedIds.insert(result.taskId) }
                        else { approvedIds.remove(result.taskId) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SeverityBadge(score: result.evaluation.score)
                    Text(result.ruleName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                Text(fileLocation(result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(result.evaluation.comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let violation = selectedViolation {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ruleInfoSection(violation)
                    Divider()
                    commentSection(violation)
                    Divider()
                    codeContextSection(violation)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "Select a Comment",
                systemImage: "text.bubble",
                description: Text("Select a violation from the list to review its details and code context.")
            )
        }
    }

    // MARK: - Rule Info

    @ViewBuilder
    private func ruleInfoSection(_ result: RuleEvaluationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SeverityBadge(score: result.evaluation.score)
                Text(result.ruleName)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Text(fileLocation(result))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                labeledValue("Model", result.modelUsed)
                labeledValue("Duration", "\(result.durationMs)ms")
                if let cost = result.costUsd {
                    labeledValue("Cost", String(format: "$%.4f", cost))
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Comment Section

    @ViewBuilder
    private func commentSection(_ result: RuleEvaluationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proposed Comment")
                .font(.headline)

            if posted {
                Text(result.evaluation.comment)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                TextEditor(text: Binding(
                    get: { editedComments[result.taskId] ?? result.evaluation.comment },
                    set: { editedComments[result.taskId] = $0 }
                ))
                .font(.body)
                .frame(minHeight: 80)
                .border(Color(nsColor: .separatorColor))
            }
        }
    }

    // MARK: - Code Context

    @ViewBuilder
    private func codeContextSection(_ result: RuleEvaluationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code Context")
                .font(.headline)

            if let content = reviewModel.readFileFromRepo(result.filePath) {
                CodeView(
                    fileContent: content,
                    fileName: result.filePath,
                    highlightedLine: result.evaluation.lineNumber
                )
                .frame(minHeight: 300, maxHeight: 500)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            } else {
                ContentUnavailableView(
                    "File Not Available",
                    systemImage: "doc.questionmark",
                    description: Text("Could not read \(result.filePath) from the repository.")
                )
                .frame(height: 120)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

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
