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
    private var inProgressAnalysis: AnalysisOutput?
    private(set) var comments: CommentPhaseOutput?

    private(set) var commentPostingState: CommentPostingState = .idle
    private(set) var submittingCommentIds: Set<String> = []
    private(set) var submittedCommentIds: Set<String> = []

    private var liveAccumulators: [LiveTranscriptAccumulator] = []
    private(set) var currentLivePhase: PRRadarPhase?
    private(set) var activeAnalysisFilePath: String?

    private(set) var operationMode: OperationMode = .idle
    private(set) var selectiveAnalysisInFlight: Set<String> = []
    private var refreshTask: Task<Void, Never>?

    // MARK: - Forwarding Properties

    var syncSnapshot: SyncSnapshot? { detail?.syncSnapshot }
    var preparation: PrepareOutput? { detail?.preparation }
    var analysis: AnalysisOutput? { inProgressAnalysis ?? detail?.analysis }
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

    var prNumber: String {
        String(metadata.number)
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

    var isSelectiveAnalysisRunning: Bool {
        !selectiveAnalysisInFlight.isEmpty
    }

    var isAIPhaseRunning: Bool {
        let aiPhases: [PRRadarPhase] = [.prepare, .analyze]
        return aiPhases.contains { phase in
            if case .running = stateFor(phase) { return true }
            return false
        }
    }

    var liveTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]] {
        guard let phase = currentLivePhase, !liveAccumulators.isEmpty else { return [:] }
        return [phase: liveAccumulators.map { $0.toClaudeAgentTranscript() }]
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
        liveAccumulators = []
        currentLivePhase = nil
        operationMode = .idle
        selectiveAnalysisInFlight = []
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
                    case .aiOutput: break
                    case .aiPrompt: break
                    case .aiToolUse: break
                    case .analysisResult: break
                    case .completed(let snapshot):
                        reloadDetail(commitHash: snapshot.commitHash)
                        let logs = runningLogs(for: .diff)
                        phaseStates[.diff] = .completed(logs: logs)
                    case .failed(let error, let logs):
                        let existingLogs = runningLogs(for: .diff)
                        phaseStates[.diff] = .failed(error: error, logs: existingLogs + logs)
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
                phaseStates[.diff] = .failed(error: error.localizedDescription, logs: logs)
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
                case .aiOutput: break
                case .aiPrompt: break
                case .aiToolUse: break
                case .analysisResult: break
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

    private func appendAIPrompt(_ context: AIPromptContext) {
        let count = liveAccumulators.count
        activeAnalysisFilePath = context.filePath
        liveAccumulators.append(LiveTranscriptAccumulator(
            identifier: "task-\(count + 1)",
            prompt: context.text,
            filePath: context.filePath,
            ruleName: context.ruleName,
            startedAt: Date()
        ))
    }

    private func appendAIOutput(_ text: String) {
        if liveAccumulators.isEmpty {
            liveAccumulators.append(LiveTranscriptAccumulator(
                identifier: "task-1",
                prompt: "",
                startedAt: Date()
            ))
        }
        liveAccumulators[liveAccumulators.count - 1].textChunks += text
    }

    private func appendAIToolUse(_ name: String) {
        guard !liveAccumulators.isEmpty else { return }
        var last = liveAccumulators[liveAccumulators.count - 1]
        if !last.textChunks.isEmpty {
            last.events.append(ClaudeAgentTranscriptEvent(type: .text, content: last.textChunks))
            last.textChunks = ""
        }
        last.events.append(ClaudeAgentTranscriptEvent(type: .toolUse, toolName: name))
        liveAccumulators[liveAccumulators.count - 1] = last
    }

    private func runPrepare() async {
        phaseStates[.prepare] = .running(logs: "")
        liveAccumulators = []
        currentLivePhase = .prepare

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
                case .aiOutput(let text):
                    appendAIOutput(text)
                case .aiPrompt(let context):
                    appendAIPrompt(context)
                case .aiToolUse(let name):
                    appendAIToolUse(name)
                case .analysisResult: break
                case .completed:
                    currentLivePhase = nil
                    let logs = runningLogs(for: .prepare)
                    reloadDetail()
                    phaseStates[.prepare] = .completed(logs: logs)
                case .failed(let error, let logs):
                    currentLivePhase = nil
                    phaseStates[.prepare] = .failed(error: error, logs: logs)
                }
            }
        } catch {
            currentLivePhase = nil
            phaseStates[.prepare] = .failed(error: error.localizedDescription, logs: "")
        }
    }

    private func runAnalyze() async {
        phaseStates[.analyze] = .running(logs: "Running evaluations...\n")
        liveAccumulators = []
        currentLivePhase = .analyze

        let useCase = AnalyzeUseCase(config: config)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, commitHash: currentCommitHash) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendLog(text, to: .analyze)
                case .aiOutput(let text):
                    appendAIOutput(text)
                case .aiPrompt(let context):
                    appendAIPrompt(context)
                case .aiToolUse(let name):
                    appendAIToolUse(name)
                case .analysisResult(let result, _):
                    activeAnalysisFilePath = nil
                    mergeAnalysisResult(result)
                case .completed:
                    inProgressAnalysis = nil
                    activeAnalysisFilePath = nil
                    currentLivePhase = nil
                    let logs = runningLogs(for: .analyze)
                    reloadDetail()
                    phaseStates[.analyze] = .completed(logs: logs)
                case .failed(let error, let logs):
                    activeAnalysisFilePath = nil
                    currentLivePhase = nil
                    phaseStates[.analyze] = .failed(error: error, logs: logs)
                }
            }
        } catch {
            activeAnalysisFilePath = nil
            currentLivePhase = nil
            let logs = runningLogs(for: .analyze)
            phaseStates[.analyze] = .failed(error: error.localizedDescription, logs: logs)
        }
    }

    func runSelectiveAnalysis(filter: AnalysisFilter) async {
        let useCase = SelectiveAnalyzeUseCase(config: config)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, filter: filter, commitHash: currentCommitHash) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendLog(text, to: .analyze)
                case .aiOutput: break
                case .aiPrompt: break
                case .aiToolUse: break
                case .analysisResult(let result, _):
                    selectiveAnalysisInFlight.remove(result.taskId)
                    mergeAnalysisResult(result)
                case .completed:
                    inProgressAnalysis = nil
                    selectiveAnalysisInFlight = []
                    reloadDetail()
                case .failed:
                    selectiveAnalysisInFlight = []
                }
            }
        } catch {
            selectiveAnalysisInFlight = []
        }
    }

    func startSelectiveAnalysis(filter: AnalysisFilter) {
        guard let tasks = preparation?.tasks, !tasks.isEmpty else { return }
        let matchingTaskIds = tasks
            .filter { filter.matches($0) }
            .map(\.taskId)
        selectiveAnalysisInFlight.formUnion(matchingTaskIds)

        Task {
            await runSelectiveAnalysis(filter: filter)
        }
    }

    private func mergeAnalysisResult(_ result: RuleEvaluationResult) {
        guard let existing = analysis else {
            let summary = AnalysisSummary(
                prNumber: Int(prNumber) ?? 0,
                evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                totalTasks: 1,
                violationsFound: result.isViolation ? 1 : 0,
                totalCostUsd: result.costUsd ?? 0,
                totalDurationMs: result.durationMs,
                results: [result]
            )
            inProgressAnalysis = AnalysisOutput(
                evaluations: [result],
                summary: summary
            )
            return
        }

        var evaluations = existing.evaluations.filter { $0.taskId != result.taskId }
        evaluations.append(result)

        let violationCount = evaluations.filter(\.isViolation).count
        let summary = AnalysisSummary(
            prNumber: Int(prNumber) ?? 0,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: evaluations.count,
            violationsFound: violationCount,
            totalCostUsd: evaluations.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: evaluations.map(\.durationMs).reduce(0, +),
            results: evaluations
        )

        inProgressAnalysis = AnalysisOutput(
            evaluations: evaluations,
            tasks: existing.tasks,
            summary: summary,
            cachedCount: existing.cachedCount
        )
    }

    private func runReport() async {
        phaseStates[.report] = .running(logs: "Generating report...\n")

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
                case .aiOutput: break
                case .aiPrompt: break
                case .aiToolUse: break
                case .analysisResult: break
                case .completed:
                    let logs = runningLogs(for: .report)
                    reloadDetail()
                    phaseStates[.report] = .completed(logs: logs)
                case .failed(let error, let logs):
                    phaseStates[.report] = .failed(error: error, logs: logs)
                }
            }
        } catch {
            let logs = runningLogs(for: .report)
            phaseStates[.report] = .failed(error: error.localizedDescription, logs: logs)
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

    struct LiveTranscriptAccumulator {
        let identifier: String
        var prompt: String
        var filePath: String?
        var ruleName: String?
        var textChunks: String = ""
        var events: [ClaudeAgentTranscriptEvent] = []
        let startedAt: Date

        func toClaudeAgentTranscript() -> ClaudeAgentTranscript {
            var finalEvents = events
            if !textChunks.isEmpty {
                finalEvents.append(ClaudeAgentTranscriptEvent(type: .text, content: textChunks))
            }
            let formatter = ISO8601DateFormatter()
            return ClaudeAgentTranscript(
                identifier: identifier,
                model: "streaming",
                startedAt: formatter.string(from: startedAt),
                prompt: prompt.isEmpty ? nil : prompt,
                filePath: filePath ?? "",
                ruleName: ruleName ?? "",
                events: finalEvents,
                costUsd: 0,
                durationMs: Int(Date().timeIntervalSince(startedAt) * 1000)
            )
        }
    }
}
