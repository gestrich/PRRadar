import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct ReviewSnapshot {
    let diff: DiffPhaseSnapshot?
    let rules: RulesPhaseOutput?
    let evaluation: EvaluationPhaseOutput?
    let report: ReportPhaseOutput?
    let comments: CommentPhaseOutput?
}

@Observable
@MainActor
final class PRModel: Identifiable, Hashable {

    private(set) var metadata: PRMetadata
    let config: PRRadarConfig
    let repoConfig: RepoConfiguration

    nonisolated let id: Int

    private(set) var analysisState: AnalysisState = .loading
    private(set) var detailState: DetailState = .unloaded
    private(set) var phaseStates: [PRRadarPhase: PhaseState] = [:]
    private(set) var diff: DiffPhaseSnapshot?
    private(set) var rules: RulesPhaseOutput?
    private(set) var evaluation: EvaluationPhaseOutput?
    private(set) var report: ReportPhaseOutput?
    private(set) var comments: CommentPhaseOutput?

    private(set) var postedComments: GitHubPullRequestComments?

    private(set) var imageURLMap: [String: String] = [:]
    private(set) var imageBaseDir: String?

    private(set) var commentPostingState: CommentPostingState = .idle
    private(set) var submittingCommentIds: Set<String> = []
    private(set) var submittedCommentIds: Set<String> = []

    private(set) var aiOutputText: String = ""
    private(set) var aiCurrentPrompt: String = ""
    private(set) var savedTranscripts: [PRRadarPhase: [BridgeTranscript]] = [:]

    private(set) var operationMode: OperationMode = .idle
    private(set) var selectiveEvaluationInFlight: Set<String> = []
    private var refreshTask: Task<Void, Never>?

    init(metadata: PRMetadata, config: PRRadarConfig, repoConfig: RepoConfiguration) {
        self.id = metadata.id
        self.metadata = metadata
        self.config = config
        self.repoConfig = repoConfig
        Task { await loadAnalysisSummary() }
    }

    // MARK: - Computed Properties

    var prNumber: String {
        String(metadata.number)
    }

    var reconciledComments: [ReviewComment] {
        ViolationService.reconcile(
            pending: evaluation?.comments ?? [],
            posted: postedComments?.reviewComments ?? []
        )
    }

    var fullDiff: GitDiff? {
        diff?.fullDiff
    }

    var effectiveDiff: GitDiff? {
        diff?.effectiveDiff
    }

    var moveReport: MoveReport? {
        diff?.moveReport
    }

    var diffFiles: [String]? {
        diff?.files
    }

    var isAnyPhaseRunning: Bool {
        phaseStates.values.contains {
            switch $0 {
            case .running, .refreshing: return true
            default: return false
            }
        }
    }

    var isSelectiveEvaluationRunning: Bool {
        !selectiveEvaluationInFlight.isEmpty
    }

    var isAIPhaseRunning: Bool {
        let aiPhases: [PRRadarPhase] = [.prepare, .analyze]
        return aiPhases.contains { phase in
            if case .running = stateFor(phase) { return true }
            return false
        }
    }


    var hasPendingComments: Bool {
        guard case .loaded(let violationCount, _, _) = analysisState, violationCount > 0 else {
            return false
        }
        // Has violations but comments phase not completed
        return !isPhaseCompleted(.report) || comments == nil
    }

    func updateMetadata(_ newMetadata: PRMetadata) {
        metadata = newMetadata
    }

    // MARK: - Analysis Summary (Lightweight)

    private func loadAnalysisSummary() async {
        do {
            let summary: EvaluationSummary = try PhaseOutputParser.parsePhaseOutput(
                config: config,
                prNumber: prNumber,
                phase: .analyze,
                filename: "summary.json"
            )
            let postedCommentCount: Int = {
                guard let comments: GitHubPullRequestComments = try? PhaseOutputParser.parsePhaseOutput(
                    config: config,
                    prNumber: prNumber,
                    phase: .sync,
                    filename: "gh-comments.json"
                ) else { return 0 }
                return comments.reviewComments.count
            }()
            analysisState = .loaded(
                violationCount: summary.violationsFound,
                evaluatedAt: summary.evaluatedAt,
                postedCommentCount: postedCommentCount
            )
        } catch {
            analysisState = .unavailable
        }
    }

    // MARK: - Detail Loading (On-Demand)

    func loadDetail() {
        guard case .unloaded = detailState else { return }
        detailState = .loading

        loadPhaseStates()
        loadCachedDiff()
        do {
            try loadCachedNonDiffOutputs()
        } catch {
            phaseStates[.sync] = .failed(
                error: "Failed to load cached outputs: \(error.localizedDescription)",
                logs: ""
            )
        }
        loadSavedTranscripts()

        detailState = .loaded(ReviewSnapshot(
            diff: self.diff,
            rules: self.rules,
            evaluation: self.evaluation,
            report: self.report,
            comments: nil
        ))
    }

    func loadCachedNonDiffOutputs() throws {
        let snapshot = LoadExistingOutputsUseCase(config: config).execute(prNumber: prNumber)
        self.rules = snapshot.rules
        self.evaluation = snapshot.evaluation
        self.report = snapshot.report

        do {
            self.postedComments = try PhaseOutputParser.parsePhaseOutput(
                config: config,
                prNumber: prNumber,
                phase: .sync,
                filename: "gh-comments.json"
            )
        } catch is PhaseOutputError {
            self.postedComments = nil
        }

        if let map: [String: String] = try? PhaseOutputParser.parsePhaseOutput(
            config: config,
            prNumber: prNumber,
            phase: .sync,
            filename: "image-url-map.json"
        ) {
            self.imageURLMap = map
            let phaseDir = OutputFileReader.phaseDirectoryPath(
                config: config, prNumber: prNumber, phase: .sync
            )
            self.imageBaseDir = "\(phaseDir)/images"
        }
    }

    // MARK: - Refresh PR Data

    func refreshPRData() async {
        operationMode = .refreshing
        defer { operationMode = .idle }
        await refreshDiff(force: true)
        do {
            try loadCachedNonDiffOutputs()
        } catch {
            let logs = runningLogs(for: .sync)
            phaseStates[.sync] = .failed(
                error: "Failed to load cached outputs: \(error.localizedDescription)",
                logs: logs
            )
        }
    }

    // MARK: - Diff Refresh

    func refreshDiff(force: Bool = false) async {
        refreshTask?.cancel()

        // Step 1: Load cached diff from disk for immediate display
        loadCachedDiff()

        // Step 2: Determine whether to fetch from GitHub
        let shouldFetch: Bool
        if force {
            shouldFetch = true
        } else if diff == nil {
            shouldFetch = true
        } else {
            shouldFetch = await isStale()
        }

        guard shouldFetch else { return }

        // Step 3: Fetch from GitHub
        let hasCachedData = diff != nil
        let logPrefix = hasCachedData ? "Refreshing" : "Fetching"
        if hasCachedData {
            phaseStates[.sync] = .refreshing(logs: "\(logPrefix) diff for PR #\(prNumber)...\n")
        } else {
            phaseStates[.sync] = .running(logs: "\(logPrefix) diff for PR #\(prNumber)...\n")
        }

        let useCase = FetchDiffUseCase(config: config)

        let task = Task {
            do {
                for try await progress in useCase.execute(prNumber: prNumber) {
                    try Task.checkCancellation()
                    switch progress {
                    case .running:
                        break
                    case .progress:
                        break
                    case .log(let text):
                        appendLog(text, to: .sync)
                    case .aiOutput: break
                    case .aiPrompt: break
                    case .aiToolUse: break
                    case .evaluationResult: break
                    case .completed(let snapshot):
                        diff = snapshot
                        let logs = runningLogs(for: .sync)
                        phaseStates[.sync] = .completed(logs: logs)
                    case .failed(let error, let logs):
                        let existingLogs = runningLogs(for: .sync)
                        phaseStates[.sync] = .failed(error: error, logs: existingLogs + logs)
                    }
                }
            } catch is CancellationError {
                // Task was cancelled — restore state
                if diff != nil {
                    phaseStates[.sync] = .completed(logs: "")
                } else {
                    phaseStates[.sync] = .idle
                }
            } catch {
                let logs = runningLogs(for: .sync)
                phaseStates[.sync] = .failed(error: error.localizedDescription, logs: logs)
            }
        }
        refreshTask = task
        await task.value
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        if diff != nil {
            phaseStates[.sync] = .completed(logs: "")
        } else {
            phaseStates[.sync] = .idle
        }
    }

    private func loadSavedTranscripts() {
        let aiPhases: [PRRadarPhase] = [.prepare, .analyze]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for phase in aiPhases {
            let files = PhaseOutputParser.listPhaseFiles(
                config: config, prNumber: prNumber, phase: phase
            )
            let transcriptFiles = files.filter { $0.hasPrefix("ai-transcript-") && $0.hasSuffix(".json") }

            var transcripts: [BridgeTranscript] = []
            for filename in transcriptFiles {
                if let data = try? PhaseOutputParser.readPhaseFile(
                    config: config, prNumber: prNumber, phase: phase, filename: filename
                ),
                   let transcript = try? decoder.decode(BridgeTranscript.self, from: data)
                {
                    transcripts.append(transcript)
                }
            }
            if !transcripts.isEmpty {
                savedTranscripts[phase] = transcripts
            }
        }
    }

    private func loadPhaseStates() {
        let allPhaseStatuses = DataPathsService.allPhaseStatuses(
            outputDir: config.absoluteOutputDir,
            prNumber: prNumber
        )

        for (phase, status) in allPhaseStatuses {
            if status.isComplete {
                phaseStates[phase] = .completed(logs: "")
            } else if !status.exists {
                phaseStates[phase] = .idle
            } else {
                let errorMsg = status.missingItems.first ?? "Incomplete"
                phaseStates[phase] = .failed(error: errorMsg, logs: "")
            }
        }
    }

    private func loadCachedDiff() {
        let snapshot = FetchDiffUseCase.parseOutput(config: config, prNumber: prNumber)
        if snapshot.fullDiff != nil || snapshot.effectiveDiff != nil {
            self.diff = snapshot
            if case .idle = stateFor(.sync) {
                phaseStates[.sync] = .completed(logs: "")
            }
        }
    }

    private func isStale() async -> Bool {
        guard let storedUpdatedAt = metadata.updatedAt else { return true }

        do {
            let (gitHub, _) = try await GitHubServiceFactory.create(
                repoPath: config.repoPath,
                tokenOverride: config.githubToken
            )
            let currentUpdatedAt = try await gitHub.getPRUpdatedAt(number: metadata.number)
            return storedUpdatedAt != currentUpdatedAt
        } catch {
            return true
        }
    }

    // MARK: - State Queries

    func stateFor(_ phase: PRRadarPhase) -> PhaseState {
        phaseStates[phase] ?? .idle
    }

    func canRunPhase(_ phase: PRRadarPhase) -> Bool {
        guard !isAnyPhaseRunning else { return false }

        switch phase {
        case .sync:
            return true
        case .prepare:
            return isPhaseCompleted(.sync)
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

    // MARK: - Phase Execution

    func runPhase(_ phase: PRRadarPhase) async {
        switch phase {
        case .sync: await runDiff()
        case .prepare: await runRules()
        case .analyze: await runEvaluate()
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
        await loadAnalysisSummary()
        return isPhaseCompleted(.report)
    }

    func resetPhase(_ phase: PRRadarPhase) {
        phaseStates[phase] = .idle
        switch phase {
        case .sync:
            diff = nil
        case .prepare:
            rules = nil
        case .analyze:
            evaluation = nil
        case .report:
            report = nil
        }
    }

    // MARK: - Phase Runners

    func runDiff() async {
        await refreshDiff(force: true)
    }

    func runComments(dryRun: Bool) async {
        commentPostingState = .running(logs: "Posting comments...\n")

        let useCase = PostCommentsUseCase(config: config)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, dryRun: dryRun) {
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
                case .evaluationResult: break
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

        let useCase = PostSingleCommentUseCase()

        do {
            let success = try await useCase.execute(
                comment: comment,
                commitSHA: commitSHA,
                prNumber: prNumber,
                repoPath: repoConfig.repoPath,
                githubToken: config.githubToken
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
        let fullPath = "\(repoConfig.repoPath)/\(relativePath)"
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

    private func runRules() async {
        phaseStates[.prepare] = .running(logs: "")
        aiOutputText = ""
        aiCurrentPrompt = ""

        let useCase = FetchRulesUseCase(config: config)
        let rulesDir = repoConfig.rulesDir.isEmpty ? nil : repoConfig.rulesDir

        do {
            for try await progress in useCase.execute(prNumber: prNumber, rulesDir: rulesDir) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendLog(text, to: .prepare)
                case .aiOutput(let text):
                    aiOutputText += text
                case .aiPrompt(let text):
                    aiCurrentPrompt = text
                case .aiToolUse: break
                case .evaluationResult: break
                case .completed(let output):
                    rules = output
                    phaseStates[.prepare] = .completed(logs: "")
                    loadSavedTranscripts()
                case .failed(let error, let logs):
                    phaseStates[.prepare] = .failed(error: error, logs: logs)
                }
            }
        } catch {
            phaseStates[.prepare] = .failed(error: error.localizedDescription, logs: "")
        }
    }

    private func runEvaluate() async {
        phaseStates[.analyze] = .running(logs: "Running evaluations...\n")
        aiOutputText = ""
        aiCurrentPrompt = ""

        let useCase = EvaluateUseCase(config: config)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendLog(text, to: .analyze)
                case .aiOutput(let text):
                    aiOutputText += text
                case .aiPrompt(let text):
                    aiCurrentPrompt = text
                case .aiToolUse: break
                case .evaluationResult(let result):
                    mergeEvaluationResult(result)
                case .completed(let output):
                    evaluation = output
                    let logs = runningLogs(for: .analyze)
                    phaseStates[.analyze] = .completed(logs: logs)
                    loadSavedTranscripts()
                case .failed(let error, let logs):
                    phaseStates[.analyze] = .failed(error: error, logs: logs)
                }
            }
        } catch {
            let logs = runningLogs(for: .analyze)
            phaseStates[.analyze] = .failed(error: error.localizedDescription, logs: logs)
        }
    }

    func runSelectiveEvaluation(filter: EvaluationFilter) async {
        let useCase = SelectiveEvaluateUseCase(config: config)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, filter: filter) {
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
                case .evaluationResult(let result):
                    selectiveEvaluationInFlight.remove(result.taskId)
                    mergeEvaluationResult(result)
                case .completed(let output):
                    evaluation = output
                    selectiveEvaluationInFlight = []
                case .failed:
                    selectiveEvaluationInFlight = []
                }
            }
        } catch {
            selectiveEvaluationInFlight = []
        }
    }

    func startSelectiveEvaluation(filter: EvaluationFilter) {
        guard let evaluation else { return }
        let matchingTaskIds = evaluation.tasks
            .filter { filter.matches($0) }
            .map(\.taskId)
        selectiveEvaluationInFlight.formUnion(matchingTaskIds)

        Task {
            await runSelectiveEvaluation(filter: filter)
        }
    }

    private func mergeEvaluationResult(_ result: RuleEvaluationResult) {
        guard let existing = evaluation else {
            let summary = EvaluationSummary(
                prNumber: Int(prNumber) ?? 0,
                evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                totalTasks: 1,
                violationsFound: result.evaluation.violatesRule ? 1 : 0,
                totalCostUsd: result.costUsd ?? 0,
                totalDurationMs: result.durationMs,
                results: [result]
            )
            evaluation = EvaluationPhaseOutput(
                evaluations: [result],
                summary: summary
            )
            return
        }

        var evaluations = existing.evaluations.filter { $0.taskId != result.taskId }
        evaluations.append(result)

        let violationCount = evaluations.filter(\.evaluation.violatesRule).count
        let summary = EvaluationSummary(
            prNumber: Int(prNumber) ?? 0,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: evaluations.count,
            violationsFound: violationCount,
            totalCostUsd: evaluations.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: evaluations.map(\.durationMs).reduce(0, +),
            results: evaluations
        )

        evaluation = EvaluationPhaseOutput(
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
            for try await progress in useCase.execute(prNumber: prNumber) {
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
                case .evaluationResult: break
                case .completed(let output):
                    report = output
                    let logs = runningLogs(for: .report)
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

    enum DetailState {
        case unloaded
        case loading
        case loaded(ReviewSnapshot)
        case failed(String)
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
