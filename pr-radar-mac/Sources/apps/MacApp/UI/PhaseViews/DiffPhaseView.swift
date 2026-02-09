import PRRadarModels
import SwiftUI

struct DiffPhaseView: View {

    let fullDiff: GitDiff
    let effectiveDiff: GitDiff?
    var comments: [PRComment]? = nil
    var evaluationSummary: EvaluationSummary? = nil
    var prModel: PRModel? = nil
    var postedReviewComments: [GitHubReviewComment] = []

    @State private var selectedTab = 0
    @State private var selectedFile: String?

    private var hasEvaluationData: Bool {
        comments != nil && evaluationSummary != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Full Diff").tag(0)
                if effectiveDiff != nil {
                    Text("Effective Diff").tag(1)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            let activeDiff = selectedTab == 0 ? fullDiff : (effectiveDiff ?? fullDiff)

            PhaseSummaryBar(items: summaryItems(for: activeDiff))
                .padding(8)

            HSplitView {
                fileList(for: activeDiff)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)

                diffContent(for: activeDiff)
            }
        }
    }

    // MARK: - Summary Bar

    private func summaryItems(for diff: GitDiff) -> [PhaseSummaryBar.Item] {
        var items: [PhaseSummaryBar.Item] = [
            .init(label: "Files:", value: "\(diff.changedFiles.count)"),
            .init(label: "Hunks:", value: "\(diff.hunks.count)"),
        ]
        if let summary = evaluationSummary {
            items.append(contentsOf: [
                .init(label: "Evaluated:", value: "\(summary.totalTasks)"),
                .init(label: "Violations:", value: "\(summary.violationsFound)"),
                .init(label: "Cost:", value: String(format: "$%.4f", summary.totalCostUsd)),
            ])
            let models = summary.modelsUsed
            if !models.isEmpty {
                let modelNames = models.map { displayName(forModelId: $0) }.joined(separator: ", ")
                items.append(.init(label: "Model:", value: modelNames))
            }
        }
        return items
    }

    // MARK: - File Sidebar

    @ViewBuilder
    private func fileList(for diff: GitDiff) -> some View {
        if hasEvaluationData {
            annotatedFileList(for: diff)
        } else {
            plainFileList(for: diff)
        }
    }

    @ViewBuilder
    private func plainFileList(for diff: GitDiff) -> some View {
        List(selection: $selectedFile) {
            Section("Changed Files") {
                ForEach(diff.changedFiles, id: \.self) { file in
                    let hunkCount = diff.getHunks(byFilePath: file).count
                    HStack {
                        Text(URL(fileURLWithPath: file).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Text("\(hunkCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(file)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func annotatedFileList(for diff: GitDiff) -> some View {
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
                        let count = (mapping.unmatchedNoFile.filter { $0.filePath == file }).count
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
    private func diffContent(for diff: GitDiff) -> some View {
        let filtered: GitDiff = {
            if let file = selectedFile {
                let hunks = diff.getHunks(byFilePath: file)
                let raw = hunks.map(\.content).joined(separator: "\n")
                return GitDiff(rawContent: raw, hunks: hunks, commitHash: diff.commitHash)
            }
            return diff
        }()

        if hasEvaluationData {
            AnnotatedDiffContentView(
                diff: filtered,
                commentMapping: commentMapping(for: diff),
                prModel: prModel,
                imageURLMap: prModel?.imageURLMap.isEmpty == false ? prModel?.imageURLMap : nil,
                imageBaseDir: prModel?.imageBaseDir
            )
        } else {
            RichDiffContentView(diff: filtered)
        }
    }

    // MARK: - Evaluation Helpers

    private func commentMapping(for diff: GitDiff) -> DiffCommentMapping {
        DiffCommentMapper.map(
            diff: diff,
            comments: comments ?? [],
            postedReviewComments: postedReviewComments
        )
    }

    private func filesWithViolationCounts(mapping: DiffCommentMapping) -> [String: Int] {
        var counts: [String: Int] = [:]
        for (file, lineMap) in mapping.commentsByFileAndLine {
            counts[file, default: 0] += lineMap.values.reduce(0) { $0 + $1.count }
        }
        for (file, comments) in mapping.unmatchedByFile {
            counts[file, default: 0] += comments.count
        }
        return counts
    }

    private func filesNotInDiff(mapping: DiffCommentMapping) -> [String] {
        let files = Set(mapping.unmatchedNoFile.map(\.filePath))
        return files.sorted()
    }

    private func maxSeverity(for file: String, mapping: DiffCommentMapping) -> Int {
        var maxScore = 0
        if let lineMap = mapping.commentsByFileAndLine[file] {
            for comments in lineMap.values {
                for comment in comments {
                    maxScore = max(maxScore, comment.score)
                }
            }
        }
        if let comments = mapping.unmatchedByFile[file] {
            for comment in comments {
                maxScore = max(maxScore, comment.score)
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
}
