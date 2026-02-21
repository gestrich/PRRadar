import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct AnalysisOutput: Sendable {
    public var evaluations: [RuleEvaluationResult]
    public var tasks: [AnalysisTaskOutput]
    public var summary: AnalysisSummary
    public var cachedCount: Int

    public static let empty = AnalysisOutput(
        evaluations: [],
        summary: AnalysisSummary(prNumber: 0, evaluatedAt: "", totalTasks: 0, violationsFound: 0, totalCostUsd: 0, totalDurationMs: 0, results: [])
    )

    public init(streaming tasks: [AnalysisTaskOutput]) {
        self.evaluations = []
        self.tasks = tasks
        self.summary = AnalysisSummary(prNumber: 0, evaluatedAt: "", totalTasks: 0, violationsFound: 0, totalCostUsd: 0, totalDurationMs: 0, results: [])
        self.cachedCount = 0
    }

    public init(evaluations: [RuleEvaluationResult], tasks: [AnalysisTaskOutput] = [], summary: AnalysisSummary, cachedCount: Int = 0) {
        self.evaluations = evaluations
        self.tasks = tasks
        self.summary = summary
        self.cachedCount = cachedCount
    }

    public mutating func appendResult(_ result: RuleEvaluationResult, prNumber: Int) {
        if let existingIndex = evaluations.firstIndex(where: { $0.taskId == result.taskId }) {
            evaluations[existingIndex] = result
        } else {
            evaluations.append(result)
        }

        let violationCount = evaluations.filter(\.isViolation).count
        summary = AnalysisSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: evaluations.count,
            violationsFound: violationCount,
            totalCostUsd: evaluations.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: evaluations.map(\.durationMs).reduce(0, +),
            results: evaluations
        )
    }

    /// Build a cumulative output from a running list of evaluations, deduplicating by taskId.
    static func cumulative(evaluations: [RuleEvaluationResult], tasks: [AnalysisTaskOutput], prNumber: Int, cachedCount: Int = 0) -> AnalysisOutput {
        var seen = Set<String>()
        var deduped: [RuleEvaluationResult] = []
        for eval in evaluations.reversed() {
            if seen.insert(eval.taskId).inserted {
                deduped.append(eval)
            }
        }
        deduped.reverse()

        let violationCount = deduped.filter(\.isViolation).count
        let summary = AnalysisSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: deduped.count,
            violationsFound: violationCount,
            totalCostUsd: deduped.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: deduped.map(\.durationMs).reduce(0, +),
            results: deduped
        )

        return AnalysisOutput(evaluations: deduped, tasks: tasks, summary: summary, cachedCount: cachedCount)
    }

    /// Merge evaluations with task metadata into structured comments.
    public var comments: [PRComment] {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
        return evaluations.compactMap { $0.violationComment(task: taskMap[$0.taskId]) }
    }
}

public struct AnalyzeUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(prNumber: Int, repoPath: String? = nil, commitHash: String? = nil) -> AsyncThrowingStream<PhaseProgress<AnalysisOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .analyze))

            Task {
                do {
                    let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

                    // Load tasks from prepare phase (sorted file-first, then rule name)
                    let tasks: [AnalysisTaskOutput] = try PhaseOutputParser.parseAllPhaseFiles(
                        config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
                    ).sorted()

                    let evalsDir = DataPathsService.phaseDirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .analyze,
                        commitHash: resolvedCommit
                    )

                    // Handle case where no tasks were generated (legitimate scenario)
                    if tasks.isEmpty {
                        continuation.yield(.log(text: "No tasks to evaluate (phase completed successfully with 0 tasks)\n"))

                        try DataPathsService.ensureDirectoryExists(at: evalsDir)

                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                        // Write empty summary
                        let summary = AnalysisSummary(
                            prNumber: prNumber,
                            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                            totalTasks: 0,
                            violationsFound: 0,
                            totalCostUsd: 0.0,
                            totalDurationMs: 0,
                            results: []
                        )
                        let summaryData = try encoder.encode(summary)
                        try summaryData.write(to: URL(fileURLWithPath: "\(evalsDir)/\(DataPathsService.summaryJSONFilename)"))

                        // Write phase_result.json
                        try PhaseResultWriter.writeSuccess(
                            phase: .analyze,
                            outputDir: config.resolvedOutputDir,
                            prNumber: prNumber,
                            commitHash: resolvedCommit,
                            stats: PhaseStats(artifactsProduced: 0)
                        )

                        let output = AnalysisOutput(evaluations: [], tasks: [], summary: summary)
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    }

                    // Partition tasks into cached (blob hash unchanged) and fresh (need evaluation)
                    let prOutputDir = "\(config.resolvedOutputDir)/\(prNumber)"
                    let (cachedResults, tasksToEvaluate) = AnalysisCacheService.partitionTasks(
                        tasks: tasks, evalsDir: evalsDir, prOutputDir: prOutputDir
                    )

                    let cachedCount = cachedResults.count
                    let freshCount = tasksToEvaluate.count
                    let totalCount = tasks.count

                    continuation.yield(.log(text: AnalysisCacheService.startMessage(cachedCount: cachedCount, freshCount: freshCount, totalCount: totalCount) + "\n"))

                    let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
                    var cumulativeEvaluations: [RuleEvaluationResult] = []

                    for (index, result) in cachedResults.enumerated() {
                        continuation.yield(.log(text: AnalysisCacheService.cachedTaskMessage(index: index + 1, totalCount: totalCount, result: result) + "\n"))
                        cumulativeEvaluations.append(result)
                        if let task = taskMap[result.taskId] {
                            continuation.yield(.taskEvent(task: task, event: .completed(result: result)))
                        }
                    }

                    var freshResults: [RuleEvaluationResult] = []
                    var durationMs = 0
                    var totalCost = 0.0

                    if !tasksToEvaluate.isEmpty {
                        let singleTaskUseCase = AnalyzeSingleTaskUseCase(config: config)
                        let startTime = Date()

                        for (index, task) in tasksToEvaluate.enumerated() {
                            let globalIndex = cachedCount + index + 1
                            let fileName = (task.focusArea.filePath as NSString).lastPathComponent
                            continuation.yield(.log(text: "[\(globalIndex)/\(totalCount)] \(fileName) — \(task.rule.name)...\n"))

                            for try await event in singleTaskUseCase.execute(task: task, prNumber: prNumber, commitHash: resolvedCommit) {
                                continuation.yield(.taskEvent(task: task, event: event))
                                if case .completed(let result) = event {
                                    freshResults.append(result)
                                    cumulativeEvaluations.append(result)
                                    let status: String
                                    switch result {
                                    case .success(let s):
                                        status = s.evaluation.violatesRule ? "VIOLATION (\(s.evaluation.score)/10)" : "OK"
                                    case .error(let e):
                                        status = "ERROR: \(e.errorMessage)"
                                    }
                                    continuation.yield(.log(text: "[\(globalIndex)/\(totalCount)] \(status)\n"))
                                }
                            }
                        }

                        durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                        totalCost = freshResults.compactMap(\.costUsd).reduce(0, +)
                    }

                    // Write task snapshots for future cache checks
                    try AnalysisCacheService.writeTaskSnapshots(tasks: tasks, evalsDir: evalsDir)

                    // Combine cached and fresh results
                    let allResults = cachedResults + freshResults
                    let violationCount = allResults.filter(\.isViolation).count

                    let summary = AnalysisSummary(
                        prNumber: prNumber,
                        evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                        totalTasks: allResults.count,
                        violationsFound: violationCount,
                        totalCostUsd: totalCost,
                        totalDurationMs: durationMs,
                        results: allResults
                    )

                    // Write summary
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let summaryData = try encoder.encode(summary)
                    try summaryData.write(to: URL(fileURLWithPath: "\(evalsDir)/\(DataPathsService.summaryJSONFilename)"))

                    // Write phase_result.json
                    try PhaseResultWriter.writeSuccess(
                        phase: .analyze,
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        commitHash: resolvedCommit,
                        stats: PhaseStats(
                            artifactsProduced: allResults.count,
                            durationMs: durationMs,
                            costUsd: totalCost
                        )
                    )

                    continuation.yield(.log(text: AnalysisCacheService.completionMessage(freshCount: freshCount, cachedCount: cachedCount, totalCount: totalCount, violationCount: violationCount) + "\n"))

                    let output = AnalysisOutput(evaluations: allResults, tasks: tasks, summary: summary, cachedCount: cachedCount)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    public static func parseOutput(config: RepositoryConfiguration, prNumber: Int, commitHash: String? = nil) throws -> AnalysisOutput {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

        let summary: AnalysisSummary = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .analyze, filename: DataPathsService.summaryJSONFilename, commitHash: resolvedCommit
        )

        let evalFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .analyze, commitHash: resolvedCommit
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var evaluations: [RuleEvaluationResult] = []
        for file in evalFiles {
            let evaluation: RuleEvaluationResult = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .analyze, filename: file, commitHash: resolvedCommit
            )
            evaluations.append(evaluation)
        }

        let tasks: [AnalysisTaskOutput] = (try? PhaseOutputParser.parseAllPhaseFiles(
            config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
        )) ?? []

        return AnalysisOutput(evaluations: evaluations, tasks: tasks, summary: summary)
    }
}
