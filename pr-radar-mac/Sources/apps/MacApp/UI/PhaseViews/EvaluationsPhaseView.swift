import PRRadarModels
import SwiftUI

struct EvaluationsPhaseView: View {

    let evaluations: [RuleEvaluationResult]
    let summary: EvaluationSummary

    @State private var severityFilter: SeverityFilter = .all
    @State private var fileFilter: String?
    @State private var ruleFilter: String?
    @State private var expandedIds: Set<String> = []

    enum SeverityFilter: String, CaseIterable {
        case all = "All"
        case minor = "Minor (1-4)"
        case moderate = "Moderate (5-7)"
        case severe = "Severe (8-10)"
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            filterBar
            evaluationsList
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summaryHeader: some View {
        PhaseSummaryBar(items: [
            .init(label: "Evaluated:", value: "\(summary.totalTasks)"),
            .init(label: "Violations:", value: "\(summary.violationsFound)"),
            .init(label: "Cost:", value: String(format: "$%.4f", summary.totalCostUsd)),
        ])
        .padding(8)
    }

    // MARK: - Filters

    @ViewBuilder
    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Severity", selection: $severityFilter) {
                ForEach(SeverityFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .frame(width: 180)

            Picker("File", selection: $fileFilter) {
                Text("All Files").tag(nil as String?)
                ForEach(availableFiles, id: \.self) { file in
                    Text(URL(fileURLWithPath: file).lastPathComponent).tag(file as String?)
                }
            }
            .frame(width: 180)

            Picker("Rule", selection: $ruleFilter) {
                Text("All Rules").tag(nil as String?)
                ForEach(availableRules, id: \.self) { rule in
                    Text(rule).tag(rule as String?)
                }
            }
            .frame(width: 180)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - List

    @ViewBuilder
    private var evaluationsList: some View {
        List {
            ForEach(filteredEvaluations, id: \.taskId) { result in
                evaluationRow(result)
            }
        }
    }

    @ViewBuilder
    private func evaluationRow(_ result: RuleEvaluationResult) -> some View {
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
                .font(.subheadline)
                .lineLimit(expandedIds.contains(result.taskId) ? nil : 2)
                .foregroundStyle(.secondary)

            if expandedIds.contains(result.taskId) {
                Divider()

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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if expandedIds.contains(result.taskId) {
                expandedIds.remove(result.taskId)
            } else {
                expandedIds.insert(result.taskId)
            }
        }
    }

    @ViewBuilder
    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    // MARK: - Filtering Logic

    private var filteredEvaluations: [RuleEvaluationResult] {
        evaluations.filter { result in
            let score = result.evaluation.score
            let passesSeverity: Bool = switch severityFilter {
            case .all: true
            case .minor: score >= 1 && score <= 4
            case .moderate: score >= 5 && score <= 7
            case .severe: score >= 8 && score <= 10
            }

            let passesFile = fileFilter == nil || result.filePath == fileFilter
            let passesRule = ruleFilter == nil || result.ruleName == ruleFilter

            return passesSeverity && passesFile && passesRule
        }
    }

    private var availableFiles: [String] {
        Array(Set(evaluations.map(\.filePath))).sorted()
    }

    private var availableRules: [String] {
        Array(Set(evaluations.map(\.ruleName))).sorted()
    }

    private func fileLocation(_ result: RuleEvaluationResult) -> String {
        if let line = result.evaluation.lineNumber {
            return "\(result.filePath):\(line)"
        }
        return result.filePath
    }
}
