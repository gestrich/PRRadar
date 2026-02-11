import PRRadarModels
import SwiftUI

struct DiffPhaseView: View {

    let fullDiff: GitDiff
    var prModel: PRModel

    @State private var selectedTab = 0
    @State private var selectedFile: String?
    @State private var showTasksForFile: String?
    @State private var showEvaluationHint = false

    private var effectiveDiff: GitDiff? { prModel.effectiveDiff }
    private var reviewComments: [ReviewComment] { prModel.reconciledComments }
    private var evaluationSummary: EvaluationSummary? { prModel.evaluation?.summary }
    private var tasks: [EvaluationTaskOutput] { prModel.rules?.tasks ?? [] }

    private var hasEvaluationData: Bool {
        evaluationSummary != nil
    }

    private var taskCountsByFile: [String: Int] {
        Dictionary(grouping: tasks, by: \.focusArea.filePath)
            .mapValues(\.count)
    }

    private var canRunSelectiveEvaluation: Bool {
        !tasks.isEmpty && hasEvaluationData
    }

    private var hasPendingTasks: Bool {
        !tasks.isEmpty && !hasEvaluationData
    }

    private var evaluationPendingHint: some View {
        Button {
            showEvaluationHint.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showEvaluationHint) {
            Text("Run Evaluate first to enable selective analysis")
                .font(.callout)
                .padding(8)
        }
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

    private func renameFrom(for file: String, in diff: GitDiff) -> String? {
        diff.getHunks(byFilePath: file).first(where: { $0.renameFrom != nil })?.renameFrom
    }

    @ViewBuilder
    private func fileList(for diff: GitDiff) -> some View {
        if hasEvaluationData {
            annotatedFileList(for: diff)
        } else {
            plainFileList(for: diff)
        }
    }

    @ViewBuilder
    private func fileNameLabel(for file: String, renameFrom: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(URL(fileURLWithPath: file).lastPathComponent)
                .lineLimit(1)
            if let renameFrom {
                Text("\u{2190} \(URL(fileURLWithPath: renameFrom).lastPathComponent)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(renameFrom)
            }
        }
    }

    @ViewBuilder
    private func plainFileList(for diff: GitDiff) -> some View {
        let postedCounts: [String: Int] = {
            let mapping = commentMapping(for: diff)
            return postedCommentCountsByFile(mapping: mapping)
        }()

        List(selection: $selectedFile) {
            Section("Changed Files") {
                ForEach(diff.changedFiles, id: \.self) { file in
                    let postedCount = postedCounts[file] ?? 0
                    let taskCount = taskCountsByFile[file] ?? 0
                    HStack {
                        fileNameLabel(for: file, renameFrom: renameFrom(for: file, in: diff))
                        Spacer()
                        fileInFlightIndicator(for: file)
                        taskBadge(count: max(taskCount, 1))
                            .opacity(taskCount > 0 ? 1 : 0)
                        postedCommentBadge(count: max(postedCount, 1))
                            .opacity(postedCount > 0 ? 1 : 0)
                    }
                    .tag(file)
                    .accessibilityIdentifier("fileRow_\(file)")
                    .contextMenu { fileContextMenu(for: file) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func annotatedFileList(for diff: GitDiff) -> some View {
        let mapping = commentMapping(for: diff)
        let allFiles = filesWithViolationCounts(mapping: mapping)
        let postedCounts = postedCommentCountsByFile(mapping: mapping)

        List(selection: $selectedFile) {
            Section("Changed Files") {
                ForEach(diff.changedFiles, id: \.self) { file in
                    let violationCount = allFiles[file] ?? 0
                    let postedCount = postedCounts[file] ?? 0
                    let taskCount = taskCountsByFile[file] ?? 0
                    HStack {
                        fileNameLabel(for: file, renameFrom: renameFrom(for: file, in: diff))
                        Spacer()
                        fileInFlightIndicator(for: file)
                        taskBadge(count: max(taskCount, 1))
                            .opacity(taskCount > 0 ? 1 : 0)
                        violationBadge(count: max(violationCount, 1), file: file, mapping: mapping)
                            .opacity(violationCount > 0 ? 1 : 0)
                        postedCommentBadge(count: max(postedCount, 1))
                            .opacity(postedCount > 0 ? 1 : 0)
                    }
                    .tag(file)
                    .contextMenu { fileContextMenu(for: file) }
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

        VStack(spacing: 0) {
            if let file = selectedFile, let taskCount = taskCountsByFile[file], taskCount > 0 {
                HStack {
                    Button {
                        showTasksForFile = file
                    } label: {
                        Label("\(taskCount) \(taskCount == 1 ? "Task" : "Tasks")", systemImage: "list.clipboard")
                            .font(.callout)
                    }
                    Spacer()
                    if canRunSelectiveEvaluation {
                        if isFileInFlight(file) {
                            ProgressView()
                                .controlSize(.small)
                        }
                        fileAnalysisMenu(for: file)
                    } else if hasPendingTasks {
                        evaluationPendingHint
                        Label("Run Analysis", systemImage: "play.circle")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
            }

            if hasEvaluationData {
                AnnotatedDiffContentView(
                    diff: filtered,
                    commentMapping: commentMapping(for: diff),
                    prModel: prModel
                )
            } else {
                RichDiffContentView(diff: filtered)
            }
        }
        .sheet(isPresented: Binding(
            get: { showTasksForFile != nil },
            set: { if !$0 { showTasksForFile = nil } }
        )) {
            if let file = showTasksForFile {
                tasksSheet(for: file)
            }
        }
    }

    // MARK: - Tasks

    @ViewBuilder
    private func tasksSheet(for file: String) -> some View {
        let fileTasks = tasks.filter { $0.focusArea.filePath == file }
        TasksPagerView(
            fileName: URL(fileURLWithPath: file).lastPathComponent,
            tasks: fileTasks,
            onDismiss: { showTasksForFile = nil }
        )
        .frame(minWidth: 500, minHeight: 300)
    }

    @ViewBuilder
    private func taskBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.blue, in: Capsule())
    }

    // MARK: - Selective Evaluation Actions

    private func rulesForFile(_ file: String) -> [String] {
        let fileTasks = tasks.filter { $0.focusArea.filePath == file }
        let ruleNames = Set(fileTasks.map(\.rule.name))
        return ruleNames.sorted()
    }

    private func focusAreasForFile(_ file: String) -> [FocusArea] {
        let fileTasks = tasks.filter { $0.focusArea.filePath == file }
        var seen = Set<String>()
        return fileTasks.compactMap { task in
            guard seen.insert(task.focusArea.focusId).inserted else { return nil }
            return task.focusArea
        }
    }

    private func rulesForFocusArea(_ focusAreaId: String) -> [String] {
        let areaTasks = tasks.filter { $0.focusArea.focusId == focusAreaId }
        let ruleNames = Set(areaTasks.map(\.rule.name))
        return ruleNames.sorted()
    }

    private func isFileInFlight(_ file: String) -> Bool {
        let fileTaskIds = Set(tasks.filter { $0.focusArea.filePath == file }.map(\.taskId))
        return !fileTaskIds.isDisjoint(with: prModel.selectiveEvaluationInFlight)
    }

    private func isFocusAreaInFlight(_ focusAreaId: String) -> Bool {
        let areaTaskIds = Set(tasks.filter { $0.focusArea.focusId == focusAreaId }.map(\.taskId))
        return !areaTaskIds.isDisjoint(with: prModel.selectiveEvaluationInFlight)
    }

    @ViewBuilder
    private func fileInFlightIndicator(for file: String) -> some View {
        if isFileInFlight(file) {
            ProgressView()
                .controlSize(.mini)
        }
    }

    @ViewBuilder
    private func fileContextMenu(for file: String) -> some View {
        if canRunSelectiveEvaluation {
            let rules = rulesForFile(file)

            Button {
                prModel.startSelectiveEvaluation(filter: EvaluationFilter(filePath: file))
            } label: {
                Label("Run All Rules", systemImage: "play.fill")
            }

            if rules.count > 1 {
                Menu("Run Rule\u{2026}") {
                    ForEach(rules, id: \.self) { rule in
                        Button(rule) {
                            prModel.startSelectiveEvaluation(
                                filter: EvaluationFilter(filePath: file, ruleNames: [rule])
                            )
                        }
                    }
                }
            }
        } else if hasPendingTasks {
            Button {} label: {
                Label("Run Evaluate first", systemImage: "info.circle")
            }
            .disabled(true)
        }
    }

    @ViewBuilder
    private func fileAnalysisMenu(for file: String) -> some View {
        let rules = rulesForFile(file)
        Menu {
            Button {
                prModel.startSelectiveEvaluation(filter: EvaluationFilter(filePath: file))
            } label: {
                Label("Run All Rules", systemImage: "play.fill")
            }

            if rules.count > 1 {
                Divider()
                ForEach(rules, id: \.self) { rule in
                    Button(rule) {
                        prModel.startSelectiveEvaluation(
                            filter: EvaluationFilter(filePath: file, ruleNames: [rule])
                        )
                    }
                }
            }
        } label: {
            Label("Run Analysis", systemImage: "play.circle")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func focusAreaContextMenu(for focusArea: FocusArea) -> some View {
        if canRunSelectiveEvaluation {
            let rules = rulesForFocusArea(focusArea.focusId)

            Button {
                prModel.startSelectiveEvaluation(
                    filter: EvaluationFilter(focusAreaId: focusArea.focusId)
                )
            } label: {
                Label("Run All Rules", systemImage: "play.fill")
            }

            if rules.count > 1 {
                Menu("Run Rule\u{2026}") {
                    ForEach(rules, id: \.self) { rule in
                        Button(rule) {
                            prModel.startSelectiveEvaluation(
                                filter: EvaluationFilter(focusAreaId: focusArea.focusId, ruleNames: [rule])
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Evaluation Helpers

    private func commentMapping(for diff: GitDiff) -> DiffCommentMapping {
        DiffCommentMapper.map(
            diff: diff,
            comments: reviewComments
        )
    }

    private func filesWithViolationCounts(mapping: DiffCommentMapping) -> [String: Int] {
        var counts: [String: Int] = [:]
        for (file, lineMap) in mapping.byFileAndLine {
            counts[file, default: 0] += lineMap.values.reduce(0) { total, comments in
                total + comments.filter { $0.state == .new }.count
            }
        }
        for (file, comments) in mapping.unmatchedByFile {
            counts[file, default: 0] += comments.filter { $0.state == .new }.count
        }
        return counts
    }

    private func filesNotInDiff(mapping: DiffCommentMapping) -> [String] {
        let files = Set(mapping.unmatchedNoFile.map(\.filePath))
        return files.sorted()
    }

    private func maxSeverity(for file: String, mapping: DiffCommentMapping) -> Int {
        var maxScore = 0
        if let lineMap = mapping.byFileAndLine[file] {
            for comments in lineMap.values {
                for comment in comments where comment.state == .new {
                    maxScore = max(maxScore, comment.score ?? 0)
                }
            }
        }
        if let comments = mapping.unmatchedByFile[file] {
            for comment in comments where comment.state == .new {
                maxScore = max(maxScore, comment.score ?? 0)
            }
        }
        return maxScore
    }

    private func postedCommentCountsByFile(mapping: DiffCommentMapping) -> [String: Int] {
        var counts: [String: Int] = [:]
        for (file, lineMap) in mapping.byFileAndLine {
            counts[file, default: 0] += lineMap.values.reduce(0) { total, comments in
                total + comments.filter { $0.state != .new }.count
            }
        }
        for (file, comments) in mapping.unmatchedByFile {
            counts[file, default: 0] += comments.filter { $0.state != .new }.count
        }
        return counts
    }

    @ViewBuilder
    private func postedCommentBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.green, in: Capsule())
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
