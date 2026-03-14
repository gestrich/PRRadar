import Logging
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature
import SwiftUI

private let logger = Logger(label: "PRRadar.DiffPhaseView")

struct DiffPhaseView: View {

    let prDiff: PRDiff
    let fullDiff: GitDiff
    var prModel: PRModel
    var onMoveTapped: ((MoveDetail) -> Void)?

    var onShowOutputForTask: ((String) -> Void)?

    @State private var selectedFile: String?
    @State private var showTasksForFile: String?
    @State private var rulePickerFile: String?
    @State private var rulePickerSets: [RuleSetGroup] = []
    @AppStorage("selectedRuleFilePaths") private var savedRuleFilePathsJSON: String = ""
    @State private var scrollToCommentID: String?
    @State private var highlightedCommentID: String?
    @State private var highlightClearTask: Task<Void, Never>?

    private var reviewComments: [ReviewComment] { prModel.reviewComments }
    private var evaluationSummary: PRReviewSummary? { prModel.analysis?.summary }
    private var tasks: [RuleRequest] { prModel.preparation?.tasks ?? [] }

    private var taskCountsByFile: [String: Int] {
        Dictionary(grouping: tasks, by: \.focusArea.filePath)
            .mapValues(\.count)
    }

    private var canRunSelectiveEvaluation: Bool {
        !tasks.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PhaseSummaryBar(items: summaryItems(for: fullDiff))
                violationNavigationButtons
            }
            .padding(8)

            HSplitView {
                fileList(for: fullDiff)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)

                diffContent(for: fullDiff)
            }
        }
        .onAppear {
            logger.info("DiffPhaseView.onAppear: selectedFile=\(selectedFile ?? "nil") pendingNav=\(prModel.pendingViolationNavigation.map(String.init(describing:)) ?? "nil") reviewComments=\(reviewComments.count)")
            syncViolationCount()
            consumePendingNavigation()
            if selectedFile == nil {
                selectedFile = fullDiff.changedFiles.first
            }
        }
        .onChange(of: prModel.pendingViolationNavigation) { _, newValue in
            if newValue != nil {
                consumePendingNavigation()
            }
        }
        .onChange(of: orderedViolations.count) { _, _ in
            syncViolationCount()
        }
    }

    // MARK: - Summary Bar

    private func summaryItems(for diff: GitDiff) -> [PhaseSummaryBar.Item] {
        var items: [PhaseSummaryBar.Item] = [
            .init(label: "Commit:", value: String(diff.commitHash.prefix(7))),
            .init(label: "Files:", value: "\(diff.changedFiles.count)"),
            .init(label: "Hunks:", value: "\(diff.hunks.count)"),
        ]
        if let summary = evaluationSummary {
            items.append(contentsOf: [
                .init(label: "Evaluated:", value: "\(summary.totalTasks)"),
                .init(label: "Violations:", value: "\(summary.violationsFound)"),
                .init(label: "Cost:", value: String(format: "$%.4f", summary.totalCostUsd)),
                .init(label: "Duration:", value: summary.formattedDuration),
            ])
            let models = prModel.analysis?.modelsUsed ?? []
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
        annotatedFileList(for: diff)
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
            if let file = selectedFile {
                let indexHash = fileIndexHash(for: file, in: diff)
                HStack {
                    Text(file)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                    if let indexHash {
                        Text(indexHash)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    if let taskCount = taskCountsByFile[file], taskCount > 0 {
                        Button {
                            showTasksForFile = file
                        } label: {
                            Label("\(taskCount) \(taskCount == 1 ? "Task" : "Tasks")", systemImage: "list.clipboard")
                                .font(.callout)
                        }
                    }
                    Spacer()
                    if canRunSelectiveEvaluation {
                        if isFileInFlight(file) {
                            ProgressView()
                                .controlSize(.small)
                        }
                        fileAnalysisMenu(for: file)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
            }

            AnnotatedDiffContentView(
                prDiff: prDiff,
                displayDiff: filtered,
                commentMapping: commentMapping(for: diff),
                prModel: prModel,
                scrollToCommentID: $scrollToCommentID,
                highlightedCommentID: highlightedCommentID,
                onMoveTapped: onMoveTapped,
                onSelectRulesForFile: { file in
                    rulePickerFile = file
                    rulePickerSets = []
                }
            )
            .id(selectedFile)
        }
        .sheet(isPresented: Binding(
            get: { showTasksForFile != nil },
            set: { if !$0 { showTasksForFile = nil } }
        )) {
            if let file = showTasksForFile {
                tasksSheet(for: file)
            }
        }
        .sheet(isPresented: Binding(
            get: { rulePickerFile != nil },
            set: { if !$0 { rulePickerFile = nil } }
        )) {
            rulePickerSheet
        }
    }

    // MARK: - Tasks

    @ViewBuilder
    private func tasksSheet(for file: String) -> some View {
        let fileTasks = tasks.filter { $0.focusArea.filePath == file }
        TasksPagerView(
            fileName: URL(fileURLWithPath: file).lastPathComponent,
            tasks: fileTasks,
            onDismiss: { showTasksForFile = nil },
            onViewOutput: { taskId in
                showTasksForFile = nil
                onShowOutputForTask?(taskId)
            }
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

    // MARK: - Selective Analysis Actions

    private func focusAreasForFile(_ file: String) -> [FocusArea] {
        prModel.focusAreas(forFile: file)
    }

    private func isFileInFlight(_ file: String) -> Bool {
        prModel.isFileStreaming(file)
    }

    private func isFocusAreaInFlight(_ focusAreaId: String) -> Bool {
        prModel.isFocusAreaStreaming(focusAreaId)
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
            Button {
                rulePickerFile = file
                rulePickerSets = []
            } label: {
                Label("Select Rules & Analyze\u{2026}", systemImage: "sparkles")
            }
        }
        if let outputId = prModel.firstOutputId(forFile: file) {
            Button {
                onShowOutputForTask?(outputId)
            } label: {
                Label("View Evaluation Output", systemImage: "text.bubble")
            }
        }
    }

    @ViewBuilder
    private func fileAnalysisMenu(for file: String) -> some View {
        let groups = prModel.ruleGroups(forFile: file)
        Menu {
            Button {
                prModel.startSelectiveAnalysis(filter: RuleFilter(filePath: file))
            } label: {
                Label("Run All Rules", systemImage: "play.fill")
            }

            Button {
                prModel.startSelectiveAnalysis(filter: RuleFilter(filePath: file), analysisMode: .regexOnly)
            } label: {
                Label("Run All Regex Rules", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Button {
                prModel.startSelectiveAnalysis(filter: RuleFilter(filePath: file), analysisMode: .scriptOnly)
            } label: {
                Label("Run All Script Rules", systemImage: "terminal")
            }

            Button {
                prModel.startSelectiveAnalysis(filter: RuleFilter(filePath: file), analysisMode: .aiOnly)
            } label: {
                Label("Run All AI Rules", systemImage: "brain")
            }

            if groups.count > 1 {
                Divider()
                ForEach(groups) { group in
                    Button(group.displayName) {
                        prModel.startSelectiveAnalysis(filter: group.filter)
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
            let groups = prModel.ruleGroups(forFocusArea: focusArea.focusId)

            Button {
                prModel.startSelectiveAnalysis(
                    filter: RuleFilter(focusAreaId: focusArea.focusId)
                )
            } label: {
                Label("Run All Rules", systemImage: "play.fill")
            }

            if groups.count > 1 {
                Menu("Run Rule\u{2026}") {
                    ForEach(groups) { group in
                        Button(group.displayName) {
                            prModel.startSelectiveAnalysis(filter: group.filter)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Analysis Helpers

    private func fileIndexHash(for file: String, in diff: GitDiff) -> String? {
        let hunks = diff.getHunks(byFilePath: file)
        guard let firstHunk = hunks.first,
              let indexLine = firstHunk.rawHeader.first(where: { $0.hasPrefix("index ") })
        else { return nil }
        let trimmed = String(indexLine.dropFirst("index ".count))
        return String(trimmed.split(separator: " ").first ?? Substring(trimmed))
    }

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
                total + comments.filter { $0.needsPosting }.count
            }
        }
        for (file, comments) in mapping.unmatchedByFile {
            counts[file, default: 0] += comments.filter { $0.needsPosting }.count
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
                for comment in comments where comment.needsPosting {
                    maxScore = max(maxScore, comment.score ?? 0)
                }
            }
        }
        if let comments = mapping.unmatchedByFile[file] {
            for comment in comments where comment.needsPosting {
                maxScore = max(maxScore, comment.score ?? 0)
            }
        }
        return maxScore
    }

    private func postedCommentCountsByFile(mapping: DiffCommentMapping) -> [String: Int] {
        var counts: [String: Int] = [:]
        for (file, lineMap) in mapping.byFileAndLine {
            counts[file, default: 0] += lineMap.values.reduce(0) { total, comments in
                total + comments.filter { $0.isPosted }.count
            }
        }
        for (file, comments) in mapping.unmatchedByFile {
            counts[file, default: 0] += comments.filter { $0.isPosted }.count
        }
        return counts
    }

    // MARK: - Rule Picker Sheet

    @ViewBuilder
    private var rulePickerSheet: some View {
        VStack(spacing: 0) {
            if rulePickerSets.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading rules...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(minWidth: 360, minHeight: 200)
                .task { rulePickerSets = await loadRuleSets() }
            } else {
                Text("Analyze File")
                    .font(.headline)
                    .padding(.top, 12)
                if let file = rulePickerFile {
                    Text(URL(fileURLWithPath: file).lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
                Divider()
                RulePickerView(
                    ruleSets: rulePickerSets,
                    initialSelectedFilePaths: savedRuleFilePaths,
                    onStart: { selectedRules in
                        saveRuleFilePaths(selectedRules)
                        let ruleFilePaths = selectedRules.map(\.filePath)
                        let file = rulePickerFile
                        rulePickerFile = nil
                        if let file {
                            prModel.startSelectiveAnalysis(
                                filter: RuleFilter(filePath: file, ruleFilePaths: ruleFilePaths)
                            )
                        }
                    },
                    onCancel: { rulePickerFile = nil }
                )
            }
        }
    }

    private func loadRuleSets() async -> [RuleSetGroup] {
        do {
            let loaded = try await LoadRulesUseCase(config: prModel.config).execute()
            return loaded.map { RuleSetGroup(rulePath: $0.rulePath, rules: $0.rules) }
        } catch {
            return []
        }
    }

    private var savedRuleFilePaths: Set<String>? {
        guard !savedRuleFilePathsJSON.isEmpty,
              let data = savedRuleFilePathsJSON.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return Set(paths)
    }

    private func saveRuleFilePaths(_ rules: [ReviewRule]) {
        let paths = rules.map(\.filePath)
        if let data = try? JSONEncoder().encode(paths),
           let json = String(data: data, encoding: .utf8) {
            savedRuleFilePathsJSON = json
        }
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

    // MARK: - Violation Navigation

    private struct ViolationLocation {
        let file: String
        let commentID: String
    }

    private var orderedViolations: [ViolationLocation] {
        let mapping = commentMapping(for: fullDiff)
        var result: [ViolationLocation] = []
        for file in fullDiff.changedFiles {
            if let lineMap = mapping.byFileAndLine[file] {
                for line in lineMap.keys.sorted() {
                    for comment in lineMap[line]! where comment.needsPosting {
                        result.append(ViolationLocation(file: file, commentID: comment.id))
                    }
                }
            }
            if let fileLevel = mapping.unmatchedByFile[file] {
                for comment in fileLevel where comment.needsPosting {
                    result.append(ViolationLocation(file: file, commentID: comment.id))
                }
            }
        }
        logger.info("orderedViolations: total=\(result.count)")
        return result
    }

    @ViewBuilder
    private var violationNavigationButtons: some View {
        let violations = orderedViolations
        if !violations.isEmpty {
            HStack(spacing: 6) {
                Button { navigateViolation(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(prModel.currentViolationIndex <= 0)

                Text(prModel.currentViolationIndex >= 0
                    ? "\(prModel.currentViolationIndex + 1) of \(violations.count)"
                    : "\(violations.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button { navigateViolation(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(prModel.currentViolationIndex >= violations.count - 1)
            }
        }
    }

    private func syncViolationCount() {
        prModel.violationCount = orderedViolations.count
    }

    private func consumePendingNavigation() {
        guard let nav = prModel.pendingViolationNavigation else { return }
        let violationCount = orderedViolations.count
        logger.info("consumePendingNavigation: nav=\(nav) violationCount=\(violationCount) reviewComments=\(reviewComments.count)")
        guard violationCount > 0 else {
            logger.info("consumePendingNavigation: no violations yet, keeping pending navigation for later")
            return
        }
        prModel.pendingViolationNavigation = nil
        switch nav {
        case .first:
            prModel.currentViolationIndex = -1
            navigateViolation(by: 1)
        case .last:
            prModel.currentViolationIndex = orderedViolations.count
            navigateViolation(by: -1)
        case .next:
            navigateViolation(by: 1)
        case .previous:
            navigateViolation(by: -1)
        }
    }

    private func navigateViolation(by delta: Int) {
        let violations = orderedViolations
        guard !violations.isEmpty else { return }

        let newIndex: Int
        if prModel.currentViolationIndex < 0 {
            newIndex = delta > 0 ? 0 : violations.count - 1
        } else {
            newIndex = prModel.currentViolationIndex + delta
        }

        guard newIndex >= 0, newIndex < violations.count else { return }
        prModel.currentViolationIndex = newIndex

        let violation = violations[newIndex]
        logger.info("navigateViolation: index=\(newIndex)/\(violations.count) file=\(URL(fileURLWithPath: violation.file).lastPathComponent)")

        if violation.file != selectedFile {
            selectedFile = violation.file
        }
        highlightClearTask?.cancel()
        highlightedCommentID = nil
        scrollToCommentID = violation.commentID
        DispatchQueue.main.async {
            highlightedCommentID = violation.commentID
            highlightClearTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                highlightedCommentID = nil
            }
        }
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
