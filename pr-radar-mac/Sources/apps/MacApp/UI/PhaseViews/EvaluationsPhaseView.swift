import PRRadarModels
import SwiftUI

struct EvaluationsPhaseView: View {

    let diff: GitDiff?
    let evaluations: [RuleEvaluationResult]
    let summary: EvaluationSummary
    var prModel: PRModel? = nil

    @State private var selectedFile: String?

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader

            if let diff {
                HSplitView {
                    fileList(diff: diff)
                        .frame(minWidth: 180, idealWidth: 220)

                    diffContent(diff: diff)
                }
            } else {
                fallbackListView
            }
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

    // MARK: - File Sidebar

    @ViewBuilder
    private func fileList(diff: GitDiff) -> some View {
        let mapping = commentMapping(for: diff)
        let allFiles = filesWithViolationCounts(mapping: mapping)

        List(selection: $selectedFile) {
            Section("Changed Files") {
                ForEach(diff.changedFiles, id: \.self) { file in
                    let violationCount = allFiles[file] ?? 0
                    HStack {
                        Text(URL(fileURLWithPath: file).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        if violationCount > 0 {
                            violationBadge(count: violationCount, file: file, mapping: mapping)
                        } else {
                            Text("\(diff.getHunks(byFilePath: file).count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(file)
                }
            }

            let extraFiles = filesNotInDiff(mapping: mapping)
            if !extraFiles.isEmpty {
                Section("Files Not in Diff") {
                    ForEach(extraFiles, id: \.self) { file in
                        let count = (mapping.unmatchedNoFile.filter { $0.evaluation.filePath == file }).count
                        HStack {
                            Text(URL(fileURLWithPath: file).lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Text("\(count)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.orange, in: Capsule())
                        }
                        .tag(file)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Diff Content

    @ViewBuilder
    private func diffContent(diff: GitDiff) -> some View {
        let filtered: GitDiff = {
            if let file = selectedFile {
                let hunks = diff.getHunks(byFilePath: file)
                let raw = hunks.map(\.content).joined(separator: "\n")
                return GitDiff(rawContent: raw, hunks: hunks, commitHash: diff.commitHash)
            }
            return diff
        }()

        AnnotatedDiffContentView(
            diff: filtered,
            commentMapping: commentMapping(for: diff),
            prModel: prModel
        )
    }

    // MARK: - Fallback List (no diff data)

    @ViewBuilder
    private var fallbackListView: some View {
        let violations = evaluations.filter(\.evaluation.violatesRule)
        if violations.isEmpty {
            ContentUnavailableView(
                "No Violations",
                systemImage: "checkmark.circle",
                description: Text("No rule violations were found.")
            )
        } else {
            List {
                ForEach(violations, id: \.taskId) { result in
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
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private func commentMapping(for diff: GitDiff) -> DiffCommentMapping {
        DiffCommentMapper.map(diff: diff, evaluations: evaluations)
    }

    private func filesWithViolationCounts(mapping: DiffCommentMapping) -> [String: Int] {
        var counts: [String: Int] = [:]
        for (file, lineMap) in mapping.commentsByFileAndLine {
            counts[file, default: 0] += lineMap.values.reduce(0) { $0 + $1.count }
        }
        for (file, evals) in mapping.unmatchedByFile {
            counts[file, default: 0] += evals.count
        }
        return counts
    }

    private func filesNotInDiff(mapping: DiffCommentMapping) -> [String] {
        let files = Set(mapping.unmatchedNoFile.map(\.evaluation.filePath))
        return files.sorted()
    }

    private func maxSeverity(for file: String, mapping: DiffCommentMapping) -> Int {
        var maxScore = 0
        if let lineMap = mapping.commentsByFileAndLine[file] {
            for evals in lineMap.values {
                for eval in evals {
                    maxScore = max(maxScore, eval.evaluation.score)
                }
            }
        }
        if let evals = mapping.unmatchedByFile[file] {
            for eval in evals {
                maxScore = max(maxScore, eval.evaluation.score)
            }
        }
        return maxScore
    }

    @ViewBuilder
    private func violationBadge(count: Int, file: String, mapping: DiffCommentMapping) -> some View {
        let severity = maxSeverity(for: file, mapping: mapping)
        let color: Color = switch severity {
        case 8...10: .red
        case 5...7: .orange
        default: .yellow
        }

        Text("\(count)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color, in: Capsule())
    }

    private func fileLocation(_ result: RuleEvaluationResult) -> String {
        if let line = result.evaluation.lineNumber {
            return "\(result.filePath):\(line)"
        }
        return result.filePath
    }
}
