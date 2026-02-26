import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct AnalyzeUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    // MARK: - Public API

    public func execute(request: PRReviewRequest) -> AsyncThrowingStream<PhaseProgress<PRReviewResult>, Error> {
        if let filter = request.filter {
            executeFiltered(prNumber: request.prNumber, filter: filter, commitHash: request.commitHash)
        } else {
            executeFullRun(prNumber: request.prNumber, commitHash: request.commitHash)
        }
    }

    // MARK: - Full Run

    private func executeFullRun(prNumber: Int, commitHash: String?) -> AsyncThrowingStream<PhaseProgress<PRReviewResult>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .analyze))

            Task {
                do {
                    let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

                    let allTasks: [RuleRequest] = try PhaseOutputParser.parseAllPhaseFiles(
                        config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
                    ).sorted()

                    let evalsDir = DataPathsService.phaseDirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .analyze,
                        commitHash: resolvedCommit
                    )

                    if allTasks.isEmpty {
                        continuation.yield(.log(text: "No tasks to evaluate (phase completed successfully with 0 tasks)\n"))

                        try DataPathsService.ensureDirectoryExists(at: evalsDir)

                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                        let summary = PRReviewSummary(
                            prNumber: prNumber,
                            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                            totalTasks: 0,
                            violationsFound: 0,
                            totalCostUsd: 0.0,
                            totalDurationMs: 0
                        )
                        let summaryData = try encoder.encode(summary)
                        try summaryData.write(to: URL(fileURLWithPath: "\(evalsDir)/\(DataPathsService.summaryJSONFilename)"))

                        try PhaseResultWriter.writeSuccess(
                            phase: .analyze,
                            outputDir: config.resolvedOutputDir,
                            prNumber: prNumber,
                            commitHash: resolvedCommit,
                            stats: PhaseStats(artifactsProduced: 0)
                        )

                        let output = PRReviewResult(taskEvaluations: [], summary: summary)
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    }

                    let evalResult = try await runEvaluations(
                        tasks: allTasks, allTasks: allTasks, prNumber: prNumber,
                        commitHash: resolvedCommit, evalsDir: evalsDir, continuation: continuation
                    )

                    try AnalysisCacheService.writeTaskSnapshots(tasks: allTasks, evalsDir: evalsDir)

                    let allResults = evalResult.cached + evalResult.fresh
                    let violationCount = allResults.filter(\.isViolation).count

                    let summary = PRReviewSummary(
                        prNumber: prNumber,
                        evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                        totalTasks: allResults.count,
                        violationsFound: violationCount,
                        totalCostUsd: evalResult.totalCost,
                        totalDurationMs: evalResult.durationMs
                    )

                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let summaryData = try encoder.encode(summary)
                    try summaryData.write(to: URL(fileURLWithPath: "\(evalsDir)/\(DataPathsService.summaryJSONFilename)"))

                    try PhaseResultWriter.writeSuccess(
                        phase: .analyze,
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        commitHash: resolvedCommit,
                        stats: PhaseStats(
                            artifactsProduced: allResults.count,
                            durationMs: evalResult.durationMs,
                            costUsd: evalResult.totalCost
                        )
                    )

                    continuation.yield(.log(text: AnalysisCacheService.completionMessage(freshCount: evalResult.fresh.count, cachedCount: evalResult.cached.count, totalCount: allTasks.count, violationCount: violationCount) + "\n"))

                    let output = PRReviewResult(tasks: allTasks, outcomes: allResults, summary: summary, cachedCount: evalResult.cached.count)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Filtered Run

    private func executeFiltered(prNumber: Int, filter: RuleFilter, commitHash: String?) -> AsyncThrowingStream<PhaseProgress<PRReviewResult>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .analyze))

            Task {
                do {
                    let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

                    let allTasks: [RuleRequest] = try PhaseOutputParser.parseAllPhaseFiles(
                        config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
                    ).sorted()

                    let filteredTasks = allTasks.filter { filter.matches($0) }

                    if filteredTasks.isEmpty {
                        continuation.yield(.log(text: "No tasks match the filter criteria\n"))
                        let output = try Self.buildMergedOutput(
                            config: config, prNumber: prNumber, allTasks: allTasks,
                            cachedCount: 0, commitHash: resolvedCommit
                        )
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    }

                    let evalsDir = DataPathsService.phaseDirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .analyze,
                        commitHash: resolvedCommit
                    )

                    continuation.yield(.log(text: "Selective evaluation: \(filteredTasks.count) tasks match filter\n"))

                    let evalResult = try await runEvaluations(
                        tasks: filteredTasks, allTasks: allTasks, prNumber: prNumber,
                        commitHash: resolvedCommit, evalsDir: evalsDir, continuation: continuation
                    )

                    let violationCount = (evalResult.cached + evalResult.fresh).filter(\.isViolation).count
                    continuation.yield(.log(text: AnalysisCacheService.completionMessage(freshCount: evalResult.fresh.count, cachedCount: evalResult.cached.count, totalCount: filteredTasks.count, violationCount: violationCount) + "\n"))

                    let output = try Self.buildMergedOutput(
                        config: config, prNumber: prNumber, allTasks: allTasks,
                        cachedCount: evalResult.cached.count, commitHash: resolvedCommit
                    )
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Shared Evaluation Loop

    private func runEvaluations(
        tasks: [RuleRequest],
        allTasks: [RuleRequest],
        prNumber: Int,
        commitHash: String?,
        evalsDir: String,
        continuation: AsyncThrowingStream<PhaseProgress<PRReviewResult>, Error>.Continuation
    ) async throws -> (cached: [RuleOutcome], fresh: [RuleOutcome], durationMs: Int, totalCost: Double) {
        let prOutputDir = "\(config.resolvedOutputDir)/\(prNumber)"
        let (cachedResults, tasksToEvaluate) = AnalysisCacheService.partitionTasks(
            tasks: tasks, evalsDir: evalsDir, prOutputDir: prOutputDir
        )

        let cachedCount = cachedResults.count
        let totalCount = tasks.count

        continuation.yield(.log(text: AnalysisCacheService.startMessage(cachedCount: cachedCount, freshCount: tasksToEvaluate.count, totalCount: totalCount) + "\n"))

        let taskMap = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.taskId, $0) })

        for (index, result) in cachedResults.enumerated() {
            continuation.yield(.log(text: AnalysisCacheService.cachedTaskMessage(index: index + 1, totalCount: totalCount, result: result) + "\n"))
            if let task = taskMap[result.taskId] {
                continuation.yield(.taskEvent(task: task, event: .completed(result: result)))
            }
        }

        var freshResults: [RuleOutcome] = []
        var durationMs = 0
        var totalCost = 0.0

        if !tasksToEvaluate.isEmpty {
            let singleTaskUseCase = AnalyzeSingleTaskUseCase(config: config)
            let startTime = Date()

            for (index, task) in tasksToEvaluate.enumerated() {
                let globalIndex = cachedCount + index + 1
                let fileName = (task.focusArea.filePath as NSString).lastPathComponent
                continuation.yield(.log(text: "[\(globalIndex)/\(totalCount)] \(fileName) — \(task.rule.name)...\n"))

                for try await event in singleTaskUseCase.execute(task: task, prNumber: prNumber, commitHash: commitHash) {
                    continuation.yield(.taskEvent(task: task, event: event))
                    if case .completed(let result) = event {
                        freshResults.append(result)
                        let status: String
                        switch result {
                        case .success(let s):
                            status = s.violatesRule ? "VIOLATION (\(s.score)/10)" : "OK"
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

        return (cached: cachedResults, fresh: freshResults, durationMs: durationMs, totalCost: totalCost)
    }

    // MARK: - Helpers

    private static func buildMergedOutput(
        config: RepositoryConfiguration,
        prNumber: Int,
        allTasks: [RuleRequest],
        cachedCount: Int,
        commitHash: String? = nil
    ) throws -> PRReviewResult {
        let evalFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .analyze, commitHash: commitHash
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var evaluations: [RuleOutcome] = []
        for file in evalFiles {
            let evaluation: RuleOutcome = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .analyze, filename: file, commitHash: commitHash
            )
            evaluations.append(evaluation)
        }

        let violationCount = evaluations.filter(\.isViolation).count
        let summary = PRReviewSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: evaluations.count,
            violationsFound: violationCount,
            totalCostUsd: evaluations.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: evaluations.map(\.durationMs).reduce(0, +)
        )

        return PRReviewResult(
            tasks: allTasks,
            outcomes: evaluations,
            summary: summary,
            cachedCount: cachedCount
        )
    }

    public static func parseOutput(config: RepositoryConfiguration, prNumber: Int, commitHash: String? = nil) throws -> PRReviewResult {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

        let summary: PRReviewSummary = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .analyze, filename: DataPathsService.summaryJSONFilename, commitHash: resolvedCommit
        )

        let evalFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .analyze, commitHash: resolvedCommit
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var evaluations: [RuleOutcome] = []
        for file in evalFiles {
            let evaluation: RuleOutcome = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .analyze, filename: file, commitHash: resolvedCommit
            )
            evaluations.append(evaluation)
        }

        let tasks: [RuleRequest] = (try? PhaseOutputParser.parseAllPhaseFiles(
            config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
        )) ?? []

        return PRReviewResult(tasks: tasks, outcomes: evaluations, summary: summary)
    }
}
