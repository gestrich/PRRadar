import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct ReviewSnapshot {
    let syncSnapshot: SyncSnapshot?
    let preparation: PrepareOutput?
    let analysis: AnalysisOutput?
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
    private(set) var syncSnapshot: SyncSnapshot?
    private(set) var preparation: PrepareOutput?
    private(set) var analysis: AnalysisOutput?
    private(set) var report: ReportPhaseOutput?
    private(set) var comments: CommentPhaseOutput?

    private(set) var postedComments: GitHubPullRequestComments?

    private(set) var imageURLMap: [String: String] = [:]
    private(set) var imageBaseDir: String?

    private(set) var commentPostingState: CommentPostingState = .idle
    private(set) var submittingCommentIds: Set<String> = []
    private(set) var submittedCommentIds: Set<String> = []

    private(set) var savedTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]] = [:]
    private var liveAccumulators: [LiveTranscriptAccumulator] = []
    private(set) var currentLivePhase: PRRadarPhase?

    private(set) var currentCommitHash: String?
    private(set) var availableCommits: [String] = []

    private(set) var operationMode: OperationMode = .idle
    private(set) var selectiveAnalysisInFlight: Set<String> = []
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
        // Has violations but comments phase not completed
        return !isPhaseCompleted(.report) || comments == nil
    }

    func updateMetadata(_ newMetadata: PRMetadata) {
        metadata = newMetadata
    }

    // MARK: - Analysis Summary (Lightweight)

    private func loadAnalysisSummary() async {
        let commit = currentCommitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
        do {
            let summary: AnalysisSummary = try PhaseOutputParser.parsePhaseOutput(
                config: config,
                prNumber: prNumber,
                phase: .analyze,
                filename: "summary.json",
                commitHash: commit
            )
            let postedCommentCount: Int = {
                guard let comments: GitHubPullRequestComments = try? PhaseOutputParser.parsePhaseOutput(
                    config: config,
                    prNumber: prNumber,
                    phase: .metadata,
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

        if currentCommitHash == nil {
            currentCommitHash = SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
        }
        refreshAvailableCommits()

        loadPhaseStates()
        loadCachedDiff()
        do {
            try loadCachedNonDiffOutputs()
        } catch {
            phaseStates[.diff] = .failed(
                error: "Failed to load cached outputs: \(error.localizedDescription)",
                logs: ""
            )
        }
        loadSavedTranscripts()

        detailState = .loaded(ReviewSnapshot(
            syncSnapshot: self.syncSnapshot,
            preparation: self.preparation,
            analysis: self.analysis,
            report: self.report,
            comments: nil
        ))
    }

    func loadCachedNonDiffOutputs() throws {
        let snapshot = LoadExistingOutputsUseCase(config: config).execute(prNumber: prNumber, commitHash: currentCommitHash)
        self.preparation = snapshot.preparation
        self.analysis = snapshot.analysis
        self.report = snapshot.report

        do {
            self.postedComments = try PhaseOutputParser.parsePhaseOutput(
                config: config,
                prNumber: prNumber,
                phase: .metadata,
                filename: "gh-comments.json"
            )
        } catch is PhaseOutputError {
            self.postedComments = nil
        }

        if let map: [String: String] = try? PhaseOutputParser.parsePhaseOutput(
            config: config,
            prNumber: prNumber,
            phase: .metadata,
            filename: "image-url-map.json"
        ) {
            self.imageURLMap = map
            let phaseDir = OutputFileReader.phaseDirectoryPath(
                config: config, prNumber: prNumber, phase: .metadata
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
            let logs = runningLogs(for: .diff)
            phaseStates[.diff] = .failed(
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
        } else if syncSnapshot == nil {
            shouldFetch = true
        } else {
            shouldFetch = await isStale()
        }

        guard shouldFetch else { return }

        // Step 3: Fetch from GitHub
        let hasCachedData = syncSnapshot != nil
        let logPrefix = hasCachedData ? "Refreshing" : "Fetching"
        if hasCachedData {
            phaseStates[.diff] = .refreshing(logs: "\(logPrefix) diff for PR #\(prNumber)...\n")
        } else {
            phaseStates[.diff] = .running(logs: "\(logPrefix) diff for PR #\(prNumber)...\n")
        }

        let useCase = SyncPRUseCase(config: config)

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
                        appendLog(text, to: .diff)
                    case .aiOutput: break
                    case .aiPrompt: break
                    case .aiToolUse: break
                    case .analysisResult: break
                    case .completed(let snapshot):
                        syncSnapshot = snapshot
                        if let newCommit = snapshot.commitHash {
                            currentCommitHash = newCommit
                            refreshAvailableCommits()
                        }
                        let logs = runningLogs(for: .diff)
                        phaseStates[.diff] = .completed(logs: logs)
                    case .failed(let error, let logs):
                        let existingLogs = runningLogs(for: .diff)
                        phaseStates[.diff] = .failed(error: error, logs: existingLogs + logs)
                    }
                }
            } catch is CancellationError {
                // Task was cancelled — restore state
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

    private func loadSavedTranscripts() {
        let aiPhases: [PRRadarPhase] = [.prepare, .analyze]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for phase in aiPhases {
            let files = PhaseOutputParser.listPhaseFiles(
                config: config, prNumber: prNumber, phase: phase, commitHash: currentCommitHash
            )
            let transcriptFiles = files.filter { $0.hasPrefix("ai-transcript-") && $0.hasSuffix(".json") }

            var transcripts: [ClaudeAgentTranscript] = []
            for filename in transcriptFiles {
                if let data = try? PhaseOutputParser.readPhaseFile(
                    config: config, prNumber: prNumber, phase: phase, filename: filename, commitHash: currentCommitHash
                ),
                   let transcript = try? decoder.decode(ClaudeAgentTranscript.self, from: data)
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
            prNumber: prNumber,
            commitHash: currentCommitHash
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
        let snapshot = SyncPRUseCase.parseOutput(config: config, prNumber: prNumber, commitHash: currentCommitHash)
        if snapshot.fullDiff != nil || snapshot.effectiveDiff != nil {
            self.syncSnapshot = snapshot
            if case .idle = stateFor(.diff) {
                phaseStates[.diff] = .completed(logs: "")
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
        currentCommitHash = commitHash
        syncSnapshot = nil
        preparation = nil
        analysis = nil
        report = nil
        comments = nil
        postedComments = nil
        savedTranscripts = [:]
        phaseStates = [:]

        loadPhaseStates()
        loadCachedDiff()
        do {
            try loadCachedNonDiffOutputs()
        } catch {
            phaseStates[.diff] = .failed(
                error: "Failed to load cached outputs: \(error.localizedDescription)",
                logs: ""
            )
        }
        loadSavedTranscripts()
        Task { await loadAnalysisSummary() }
    }

    private func refreshAvailableCommits() {
        let analysisRoot = "\(config.absoluteOutputDir)/\(prNumber)/\(DataPathsService.analysisDirectoryName)"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: analysisRoot) else {
            availableCommits = []
            return
        }
        availableCommits = dirs.filter { !$0.hasPrefix(".") }.sorted()
    }

    // MARK: - Phase Execution

    func runPhase(_ phase: PRRadarPhase) async {
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
        await loadAnalysisSummary()
        return isPhaseCompleted(.report)
    }

    func resetPhase(_ phase: PRRadarPhase) {
        phaseStates[phase] = .idle
        switch phase {
        case .metadata:
            break
        case .diff:
            syncSnapshot = nil
        case .prepare:
            preparation = nil
        case .analyze:
            analysis = nil
        case .report:
            report = nil
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

    private func appendAIPrompt(_ text: String) {
        let count = liveAccumulators.count
        liveAccumulators.append(LiveTranscriptAccumulator(
            identifier: "task-\(count + 1)",
            prompt: text,
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
        let rulesDir = repoConfig.rulesDir.isEmpty ? nil : repoConfig.rulesDir

        do {
            for try await progress in useCase.execute(prNumber: prNumber, rulesDir: rulesDir, commitHash: currentCommitHash) {
                switch progress {
                case .running:
                    break
                case .progress:
                    break
                case .log(let text):
                    appendLog(text, to: .prepare)
                case .aiOutput(let text):
                    appendAIOutput(text)
                case .aiPrompt(let text):
                    appendAIPrompt(text)
                case .aiToolUse(let name):
                    appendAIToolUse(name)
                case .analysisResult: break
                case .completed(let output):
                    preparation = output
                    currentLivePhase = nil
                    phaseStates[.prepare] = .completed(logs: "")
                    loadSavedTranscripts()
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
                case .aiPrompt(let text):
                    appendAIPrompt(text)
                case .aiToolUse(let name):
                    appendAIToolUse(name)
                case .analysisResult(let result):
                    mergeAnalysisResult(result)
                case .completed(let output):
                    analysis = output
                    currentLivePhase = nil
                    let logs = runningLogs(for: .analyze)
                    phaseStates[.analyze] = .completed(logs: logs)
                    loadSavedTranscripts()
                case .failed(let error, let logs):
                    currentLivePhase = nil
                    phaseStates[.analyze] = .failed(error: error, logs: logs)
                }
            }
        } catch {
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
                case .analysisResult(let result):
                    selectiveAnalysisInFlight.remove(result.taskId)
                    mergeAnalysisResult(result)
                case .completed(let output):
                    analysis = output
                    selectiveAnalysisInFlight = []
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
                violationsFound: result.evaluation.violatesRule ? 1 : 0,
                totalCostUsd: result.costUsd ?? 0,
                totalDurationMs: result.durationMs,
                results: [result]
            )
            analysis = AnalysisOutput(
                evaluations: [result],
                summary: summary
            )
            return
        }

        var evaluations = existing.evaluations.filter { $0.taskId != result.taskId }
        evaluations.append(result)

        let violationCount = evaluations.filter(\.evaluation.violatesRule).count
        let summary = AnalysisSummary(
            prNumber: Int(prNumber) ?? 0,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: evaluations.count,
            violationsFound: violationCount,
            totalCostUsd: evaluations.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: evaluations.map(\.durationMs).reduce(0, +),
            results: evaluations
        )

        analysis = AnalysisOutput(
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

    struct LiveTranscriptAccumulator {
        let identifier: String
        var prompt: String
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
                events: finalEvents,
                costUsd: 0,
                durationMs: Int(Date().timeIntervalSince(startedAt) * 1000)
            )
        }
    }
}
