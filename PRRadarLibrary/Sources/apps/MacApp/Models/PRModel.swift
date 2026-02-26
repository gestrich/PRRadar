import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

@Observable
@MainActor
final class PRModel: Identifiable, Hashable {

    private(set) var metadata: PRMetadata
    let config: RepositoryConfiguration

    nonisolated let id: Int

    private(set) var analysisState: AnalysisState = .loading
    private(set) var detailLoaded = false
    private(set) var phaseStates: [PRRadarPhase: PhaseState] = [:]

    private(set) var detail: PRDetail?
    private var inProgressAnalysis: PRReviewResult?
    private(set) var comments: CommentPhaseOutput?

    private(set) var commentPostingState: CommentPostingState = .idle
    private(set) var submittingCommentIds: Set<String> = []
    private(set) var submittedCommentIds: Set<String> = []

    private(set) var evaluations: [String: TaskEvaluation] = [:]
    private var prepareAccumulator: LiveTranscriptAccumulator?
    private(set) var operationMode: OperationMode = .idle
    private var refreshTask: Task<Void, Never>?

    // MARK: - Forwarding Properties

    var syncSnapshot: SyncSnapshot? { detail?.syncSnapshot }
    var preparation: PrepareOutput? { detail?.preparation }
    var analysis: PRReviewResult? { inProgressAnalysis ?? detail?.analysis }
    var report: ReportPhaseOutput? { detail?.report }
    var postedComments: GitHubPullRequestComments? { detail?.postedComments }
    var imageURLMap: [String: String] { detail?.imageURLMap ?? [:] }
    var imageBaseDir: String? { detail?.imageBaseDir }
    var savedTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]] { detail?.savedTranscripts ?? [:] }
    var currentCommitHash: String? { detail?.commitHash }
    var availableCommits: [String] { detail?.availableCommits ?? [] }

    init(metadata: PRMetadata, config: RepositoryConfiguration) {
        self.id = metadata.id
        self.metadata = metadata
        self.config = config
        Task { reloadDetail() }
    }

    // MARK: - Computed Properties

    var prNumber: Int {
        metadata.number
    }

    var reconciledComments: [ReviewComment] {
        ViolationService.reconcile(
            pending: analysis?.comments ?? [],
            posted: postedComments?.reviewComments ?? []
        )
    }

    var fullDiff: GitDiff? {
        syncSnapshot?.fullDiff
    }

    var effectiveDiff: GitDiff? {
        syncSnapshot?.effectiveDiff
    }

    var moveReport: MoveReport? {
        syncSnapshot?.moveReport
    }

    var diffFiles: [String]? {
        syncSnapshot?.files
    }

    var isAnyPhaseRunning: Bool {
        phaseStates.values.contains {
            switch $0 {
            case .running, .refreshing: return true
            default: return false
            }
        }
    }

    var isAIPhaseRunning: Bool {
        prepareAccumulator != nil || evaluations.values.contains { $0.isStreaming }
    }

    var allTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]] {
        var result: [PRRadarPhase: [ClaudeAgentTranscript]] = [:]

        if let acc = prepareAccumulator {
            result[.prepare] = [acc.toClaudeAgentTranscript()]
        } else if let prepareTranscripts = savedTranscripts[.prepare], !prepareTranscripts.isEmpty {
            result[.prepare] = prepareTranscripts
        }

        let analyzeTranscripts = evaluations.values
            .sorted(by: { $0.request < $1.request })
            .compactMap { $0.transcript }
        if !analyzeTranscripts.isEmpty {
            result[.analyze] = analyzeTranscripts
        }

        return result
    }

    var hasPendingComments: Bool {
        guard case .loaded(let violationCount, _, _) = analysisState, violationCount > 0 else {
            return false
        }
        return !isPhaseCompleted(.report) || comments == nil
    }

    func updateMetadata(_ newMetadata: PRMetadata) {
        metadata = newMetadata
    }

    func resetAfterDataDeletion(metadata newMetadata: PRMetadata) {
        metadata = newMetadata
        detail = nil
        inProgressAnalysis = nil
        comments = nil
        analysisState = .loading
        detailLoaded = false
        phaseStates = [:]
        commentPostingState = .idle
        submittingCommentIds = []
        submittedCommentIds = []
        evaluations = [:]
        prepareAccumulator = nil
        operationMode = .idle
        refreshTask?.cancel()
        refreshTask = nil
        reloadDetail()
    }

    // MARK: - Detail Loading

    private func reloadDetail(commitHash: String? = nil) {
        let newDetail = LoadPRDetailUseCase(config: config)
            .execute(prNumber: prNumber, commitHash: commitHash ?? detail?.commitHash)
        applyDetail(newDetail)
    }

    private func applyDetail(_ newDetail: PRDetail) {
        self.detail = newDetail

        for (phase, status) in newDetail.phaseStatuses {
            if case .running = phaseStates[phase] { continue }
            if case .refreshing = phaseStates[phase] { continue }
            if status.isComplete {
                phaseStates[phase] = .completed(logs: "")
            } else if !status.exists {
                phaseStates[phase] = .idle
            } else {
                phaseStates[phase] = .failed(error: status.missingItems.first ?? "Incomplete", logs: "")
            }
        }

        if let tasks = newDetail.preparation?.tasks {
            let outcomeMap = Dictionary(
                (newDetail.analysis?.evaluations ?? []).map { ($0.taskId, $0) },
                uniquingKeysWith: { _, new in new }
            )
            let transcriptMap = Dictionary(
                (newDetail.savedTranscripts[.analyze] ?? []).map {
                    ("\($0.filePath):\($0.ruleName)", $0)
                },
                uniquingKeysWith: { _, new in new }
            )
            var newEvaluations: [String: TaskEvaluation] = [:]
            for task in tasks {
                var eval = TaskEvaluation(request: task, phase: .analyze)
                eval.outcome = outcomeMap[task.taskId]
                eval.savedTranscript = transcriptMap["\(task.focusArea.filePath):\(task.rule.name)"]
                newEvaluations[task.taskId] = eval
            }
            evaluations = newEvaluations
        }

        if let summary = newDetail.analysisSummary {
            let postedCount = newDetail.postedComments?.reviewComments.count ?? 0
            analysisState = .loaded(
                violationCount: summary.violationsFound,
                evaluatedAt: summary.evaluatedAt,
                postedCommentCount: postedCount
            )
        } else if newDetail.syncSnapshot != nil {
            analysisState = .unavailable
        }
    }

    func loadDetail() {
        guard !detailLoaded else { return }
        reloadDetail()
        detailLoaded = true
    }

    // MARK: - Refresh PR Data

    func refreshPRData() async {
        operationMode = .refreshing
        defer { operationMode = .idle }
        await refreshDiff(force: true)
    }

    // MARK: - Diff Refresh

    func refreshDiff(force: Bool = false) async {
        refreshTask?.cancel()

        let hasCachedData = syncSnapshot != nil
        if hasCachedData {
            phaseStates[.diff] = .refreshing(logs: "Checking PR #\(prNumber)...\n")
        } else {
            phaseStates[.diff] = .running(logs: "Fetching diff for PR #\(prNumber)...\n")
        }

        let useCase = SyncPRUseCase(config: config)

        let task = Task {
            do {
                for try await progress in useCase.execute(prNumber: prNumber, force: force) {
                    try Task.checkCancellation()
                    switch progress {
                    case .running:
                        break
                    case .progress:
                        break
                    case .log(let text):
                        appendLog(text, to: .diff)
                    case .prepareOutput: break
                    case .prepareToolUse: break
                    case .taskEvent: break
                    case .completed(let snapshot):
                        reloadDetail(commitHash: snapshot.commitHash)
                        let logs = runningLogs(for: .diff)
                        phaseStates[.diff] = .completed(logs: logs)
                    case .failed(let error, let logs):
                        let existingLogs = runningLogs(for: .diff)
                        failPhase(.diff, error: error, logs: existingLogs + logs)
                    }
                }
            } catch is CancellationError {
                if syncSnapshot != nil {
                    phaseStates[.diff] = .completed(logs: "")
                } else {
                    phaseStates[.diff] = .idle
                }
            } catch {
                let logs = runningLogs(for: .diff)
                failPhase(.diff, error: error.localizedDescription, logs: logs)
            }
        }
        refreshTask = task
        await task.value
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        if syncSnapshot != nil {
            phaseStates[.diff] = .completed(logs: "")
        } else {
            phaseStates[.diff] = .idle
        }
    }

    // MARK: - State Queries

    func stateFor(_ phase: PRRadarPhase) -> PhaseState {
        phaseStates[phase] ?? .idle
    }

    func canRunPhase(_ phase: PRRadarPhase) -> Bool {
        guard !isAnyPhaseRunning else { return false }

        switch phase {
        case .metadata:
            return true
        case .diff:
            return true
        case .prepare:
            return isPhaseCompleted(.diff)
        case .analyze:
            return isPhaseCompleted(.prepare)
        case .report:
            return isPhaseCompleted(.analyze)
        }
    }

    func isPhaseCompleted(_ phase: PRRadarPhase) -> Bool {
        if case .completed = stateFor(phase) { return true }
        return false
    }

    // MARK: - Commit Switching

    func switchToCommit(_ commitHash: String) {
        inProgressAnalysis = nil
        comments = nil
        phaseStates = [:]
        reloadDetail(commitHash: commitHash)
    }

    // MARK: - Phase Execution

    func runPhase(_ phase: PRRadarPhase) async {
        let shouldManageMode = operationMode == .idle
        if shouldManageMode {
            operationMode = phase == .diff ? .refreshing : .analyzing
        }
        defer { if shouldManageMode { operationMode = .idle } }
        switch phase {
        case .metadata: break
        case .diff: await runSync()
        case .prepare: await runPrepare()
        case .analyze: await runAnalyze()
        case .report: await runReport()
        }
    }

    @discardableResult
    func runAnalysis() async -> Bool {
        loadDetail()
        operationMode = .analyzing
        defer { operationMode = .idle }
        let phases: [PRRadarPhase] = [.prepare, .analyze, .report]
        for phase in phases {
            guard canRunPhase(phase) else { break }
            await runPhase(phase)
            if case .failed = stateFor(phase) { break }
        }
        return isPhaseCompleted(.report)
    }

    func resetPhase(_ phase: PRRadarPhase) {
        phaseStates[phase] = .idle
        switch phase {
        case .metadata:
            break
        case .diff, .prepare, .report:
            reloadDetail()
        case .analyze:
            inProgressAnalysis = nil
            reloadDetail()
        }
    }

    // MARK: - Phase Runners

    func runSync() async {
        await refreshDiff(force: true)
    }

    func runComments(dryRun: Bool) async {
        commentPostingState = .running(logs: "Posting comments...\n")

        let useCase = PostCommentsUseCase(config: config)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, dryRun: dryRun, commitHash: currentCommitHash) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendCommentLog(text)
                case .prepareOutput: break
                case .prepareToolUse: break
                case .taskEvent: break
                case .completed(let output):
                    comments = output
                    let logs = commentPostingLogs
                    commentPostingState = .completed(logs: logs)
                case .failed(let error, let logs):
                    commentPostingState = .failed(error: error, logs: logs)
                }
            }
        } catch {
            let logs = commentPostingLogs
            commentPostingState = .failed(error: error.localizedDescription, logs: logs)
        }
    }

    // MARK: - Single Comment Submission

    func submitSingleComment(_ comment: PRComment) async {
        guard let fullDiff else { return }
        let commitSHA = fullDiff.commitHash

        submittingCommentIds.insert(comment.id)

        let useCase = PostSingleCommentUseCase(config: config)

        do {
            let success = try await useCase.execute(
                comment: comment,
                commitSHA: commitSHA,
                prNumber: prNumber
            )

            submittingCommentIds.remove(comment.id)
            if success {
                submittedCommentIds.insert(comment.id)
            }
        } catch {
            submittingCommentIds.remove(comment.id)
        }
    }

    // MARK: - File Access

    func readFileFromRepo(_ relativePath: String) -> String? {
        let fullPath = "\(config.repoPath)/\(relativePath)"
        return try? String(contentsOfFile: fullPath, encoding: .utf8)
    }

    // MARK: - Hashable

    nonisolated static func == (lhs: PRModel, rhs: PRModel) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Helpers

    private func runningLogs(for phase: PRRadarPhase) -> String {
        switch phaseStates[phase] {
        case .running(let logs), .refreshing(let logs): return logs
        default: return ""
        }
    }

    private func appendLog(_ text: String, to phase: PRRadarPhase) {
        let existing: String
        let isRefreshing: Bool
        switch phaseStates[phase] {
        case .running(let logs):
            existing = logs
            isRefreshing = false
        case .refreshing(let logs):
            existing = logs
            isRefreshing = true
        default:
            existing = ""
            isRefreshing = false
        }
        if isRefreshing {
            phaseStates[phase] = .refreshing(logs: existing + text)
        } else {
            phaseStates[phase] = .running(logs: existing + text)
        }
    }

    private var commentPostingLogs: String {
        if case .running(let logs) = commentPostingState { return logs }
        return ""
    }

    private func appendCommentLog(_ text: String) {
        let existing = commentPostingLogs
        commentPostingState = .running(logs: existing + text)
    }

    func isFileStreaming(_ filePath: String) -> Bool {
        evaluations.values.contains { $0.isStreaming && $0.request.focusArea.filePath == filePath }
    }

    func isFocusAreaStreaming(_ focusId: String) -> Bool {
        evaluations.values.contains { $0.isStreaming && $0.request.focusArea.focusId == focusId }
    }

    private func startPhase(_ phase: PRRadarPhase, logs: String = "") {
        phaseStates[phase] = .running(logs: logs)
    }

    private func completePhase(_ phase: PRRadarPhase) {
        let logs = runningLogs(for: phase)
        reloadDetail()
        phaseStates[phase] = .completed(logs: logs)
    }

    private func failPhase(_ phase: PRRadarPhase, error: String, logs: String) {
        phaseStates[phase] = .failed(error: error, logs: logs)
    }

    private func runPrepare() async {
        startPhase(.prepare)
        prepareAccumulator = nil

        let useCase = PrepareUseCase(config: config)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, rulesDir: config.resolvedRulesDir, commitHash: currentCommitHash) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendLog(text, to: .prepare)
                case .prepareOutput(let text):
                    if prepareAccumulator == nil {
                        prepareAccumulator = LiveTranscriptAccumulator(
                            identifier: "prepare",
                            prompt: "",
                            startedAt: Date()
                        )
                    }
                    prepareAccumulator?.textChunks += text
                case .prepareToolUse(let name):
                    prepareAccumulator?.flushTextAndAppendToolUse(name)
                case .taskEvent: break
                case .completed:
                    prepareAccumulator = nil
                    completePhase(.prepare)
                case .failed(let error, let logs):
                    prepareAccumulator = nil
                    failPhase(.prepare, error: error, logs: logs)
                }
            }
        } catch {
            prepareAccumulator = nil
            failPhase(.prepare, error: error.localizedDescription, logs: "")
        }
    }

    private func runAnalyze() async {
        startPhase(.analyze, logs: "Running evaluations...\n")
        for key in evaluations.keys { evaluations[key]?.accumulator = nil }
        let tasks = preparation?.tasks ?? []
        inProgressAnalysis = PRReviewResult(streaming: tasks)
        let useCase = AnalyzeUseCase(config: config)
        let request = PRReviewRequest(prNumber: prNumber, commitHash: currentCommitHash)

        do {
            for try await progress in useCase.execute(request: request) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendLog(text, to: .analyze)
                case .prepareOutput: break
                case .prepareToolUse: break
                case .taskEvent(let task, let event):
                    handleTaskEvent(task, event)
                case .completed:
                    inProgressAnalysis = nil
                    for key in evaluations.keys { evaluations[key]?.accumulator = nil }
                    completePhase(.analyze)
                case .failed(let error, let logs):
                    for key in evaluations.keys { evaluations[key]?.accumulator = nil }
                    failPhase(.analyze, error: error, logs: logs)
                }
            }
        } catch {
            for key in evaluations.keys { evaluations[key]?.accumulator = nil }
            let logs = runningLogs(for: .analyze)
            failPhase(.analyze, error: error.localizedDescription, logs: logs)
        }
    }

    private func runFilteredAnalysis(filter: RuleFilter) async {
        inProgressAnalysis = detail?.analysis ?? PRReviewResult(streaming: preparation?.tasks ?? [])
        for key in evaluations.keys { evaluations[key]?.accumulator = nil }

        let useCase = AnalyzeUseCase(config: config)
        let request = PRReviewRequest(prNumber: prNumber, filter: filter, commitHash: currentCommitHash)

        do {
            for try await progress in useCase.execute(request: request) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendLog(text, to: .analyze)
                case .prepareOutput: break
                case .prepareToolUse: break
                case .taskEvent(let task, let event):
                    handleTaskEvent(task, event)
                case .completed:
                    inProgressAnalysis = nil
                    for key in evaluations.keys { evaluations[key]?.accumulator = nil }
                    reloadDetail()
                case .failed:
                    for key in evaluations.keys { evaluations[key]?.accumulator = nil }
                }
            }
        } catch {
            for key in evaluations.keys { evaluations[key]?.accumulator = nil }
        }
    }

    private func handleTaskEvent(_ task: RuleRequest, _ event: TaskProgress) {
        switch event {
        case .prompt(let text):
            let count = evaluations.values.filter { $0.accumulator != nil }.count
            evaluations[task.taskId]?.accumulator = LiveTranscriptAccumulator(
                identifier: "task-\(count + 1)",
                prompt: text,
                filePath: task.focusArea.filePath,
                ruleName: task.rule.name,
                startedAt: Date()
            )
        case .output(let text):
            evaluations[task.taskId]?.accumulator?.textChunks += text
        case .toolUse(let name):
            evaluations[task.taskId]?.accumulator?.flushTextAndAppendToolUse(name)
        case .completed(let result):
            evaluations[task.taskId]?.outcome = result
            inProgressAnalysis?.appendResult(result, prNumber: prNumber)
        }
    }

    func startSelectiveAnalysis(filter: RuleFilter) {
        guard let tasks = preparation?.tasks, !tasks.isEmpty else { return }
        let matchingTasks = tasks.filter { filter.matches($0) }
        guard !matchingTasks.isEmpty else { return }

        if matchingTasks.count == 1, let task = matchingTasks.first {
            Task {
                await runSingleAnalysis(task: task)
            }
        } else {
            Task {
                await runFilteredAnalysis(filter: filter)
            }
        }
    }

    private func runSingleAnalysis(task: RuleRequest) async {
        evaluations[task.taskId]?.accumulator = nil
        inProgressAnalysis = detail?.analysis ?? PRReviewResult(streaming: preparation?.tasks ?? [])

        let useCase = AnalyzeSingleTaskUseCase(config: config)

        do {
            for try await event in useCase.execute(task: task, prNumber: prNumber, commitHash: currentCommitHash) {
                handleTaskEvent(task, event)
            }
            evaluations[task.taskId]?.accumulator = nil
            reloadDetail()
        } catch {
            evaluations[task.taskId]?.accumulator = nil
            failPhase(.analyze, error: error.localizedDescription, logs: "")
        }

        inProgressAnalysis = nil
    }

    private func runReport() async {
        startPhase(.report, logs: "Generating report...\n")

        let useCase = GenerateReportUseCase(config: config)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, commitHash: currentCommitHash) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendLog(text, to: .report)
                case .prepareOutput: break
                case .prepareToolUse: break
                case .taskEvent: break
                case .completed:
                    completePhase(.report)
                case .failed(let error, let logs):
                    failPhase(.report, error: error, logs: logs)
                }
            }
        } catch {
            let logs = runningLogs(for: .report)
            failPhase(.report, error: error.localizedDescription, logs: logs)
        }
    }

    // MARK: - Nested Types

    enum OperationMode {
        case idle
        case refreshing
        case analyzing
    }

    enum AnalysisState {
        case loading
        case loaded(violationCount: Int, evaluatedAt: String, postedCommentCount: Int)
        case unavailable
    }

    enum PhaseState: Sendable {
        case idle
        case running(logs: String)
        case refreshing(logs: String)
        case completed(logs: String)
        case failed(error: String, logs: String)
    }

    enum CommentPostingState {
        case idle
        case running(logs: String)
        case completed(logs: String)
        case failed(error: String, logs: String)
    }
}
