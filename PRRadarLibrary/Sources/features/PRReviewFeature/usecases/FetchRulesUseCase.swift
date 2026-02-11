import CLISDK
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct RulesPhaseOutput: Sendable {
    public let focusAreas: [FocusArea]
    public let rules: [ReviewRule]
    public let tasks: [EvaluationTaskOutput]

    public init(focusAreas: [FocusArea], rules: [ReviewRule], tasks: [EvaluationTaskOutput]) {
        self.focusAreas = focusAreas
        self.rules = rules
        self.tasks = tasks
    }
}

public struct FetchRulesUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(prNumber: String, rulesDir: String?) -> AsyncThrowingStream<PhaseProgress<RulesPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .focusAreas))

            Task {
                do {
                    guard let prNum = Int(prNumber) else {
                        continuation.yield(.failed(error: "Invalid PR number: \(prNumber)", logs: ""))
                        continuation.finish()
                        return
                    }

                    let prOutputDir = "\(config.absoluteOutputDir)/\(prNumber)"

                    // Phase 2: Generate focus areas
                    continuation.yield(.log(text: "Generating focus areas...\n"))

                    let diffSnapshot = FetchDiffUseCase.parseOutput(config: config, prNumber: prNumber)
                    guard let fullDiff = diffSnapshot.effectiveDiff ?? diffSnapshot.fullDiff else {
                        continuation.yield(.failed(error: "No diff data found. Run diff phase first.", logs: ""))
                        continuation.finish()
                        return
                    }

                    let bridgeClient = ClaudeBridgeClient(pythonEnvironment: PythonEnvironment(bridgeScriptPath: config.bridgeScriptPath), cliClient: CLIClient())
                    let focusGenerator = FocusGeneratorService(bridgeClient: bridgeClient)

                    let focusDir = "\(prOutputDir)/\(PRRadarPhase.focusAreas.rawValue)"

                    let focusResults = try await focusGenerator.generateAllFocusAreas(
                        hunks: fullDiff.hunks,
                        prNumber: prNum,
                        requestedTypes: [.file],
                        transcriptDir: focusDir,
                        onAIText: { text in
                            continuation.yield(.aiOutput(text: text))
                        },
                        onAIToolUse: { name in
                            continuation.yield(.aiToolUse(name: name))
                        }
                    )
                    try FileManager.default.createDirectory(atPath: focusDir, withIntermediateDirectories: true)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                    var allFocusAreas: [FocusArea] = []
                    var totalCost = 0.0
                    for (focusType, result) in focusResults {
                        allFocusAreas.append(contentsOf: result.focusAreas)
                        totalCost += result.generationCostUsd
                        let typeOutput = FocusAreaTypeOutput(
                            prNumber: prNum,
                            generatedAt: ISO8601DateFormatter().string(from: Date()),
                            focusType: focusType.rawValue,
                            focusAreas: result.focusAreas,
                            totalHunksProcessed: result.totalHunksProcessed,
                            generationCostUsd: result.generationCostUsd
                        )
                        let data = try encoder.encode(typeOutput)
                        try data.write(to: URL(fileURLWithPath: "\(focusDir)/\(DataPathsService.dataFilePrefix)\(focusType.rawValue).json"))
                    }

                    // Write phase_result.json for phase 2 (focus areas)
                    try PhaseResultWriter.writeSuccess(
                        phase: .focusAreas,
                        outputDir: config.absoluteOutputDir,
                        prNumber: prNumber,
                        stats: PhaseStats(
                            artifactsProduced: allFocusAreas.count,
                            costUsd: totalCost
                        )
                    )

                    continuation.yield(.running(phase: .rules))
                    continuation.yield(.log(text: "Focus areas: \(allFocusAreas.count) generated\n"))

                    // Phase 3: Load rules
                    guard let rulesPath = rulesDir, !rulesPath.isEmpty else {
                        continuation.yield(.failed(error: "No rules directory specified", logs: ""))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.log(text: "Loading rules from \(rulesPath)...\n"))

                    let gitOps = GitHubServiceFactory.createGitOps()
                    let ruleLoader = RuleLoaderService(gitOps: gitOps)
                    let allRules = try await ruleLoader.loadAllRules(rulesDir: rulesPath)

                    let rulesOutputDir = "\(prOutputDir)/\(PRRadarPhase.rules.rawValue)"
                    try FileManager.default.createDirectory(atPath: rulesOutputDir, withIntermediateDirectories: true)
                    let rulesData = try encoder.encode(allRules)
                    try rulesData.write(to: URL(fileURLWithPath: "\(rulesOutputDir)/all-rules.json"))

                    // Write phase_result.json for phase 3 (rules)
                    try PhaseResultWriter.writeSuccess(
                        phase: .rules,
                        outputDir: config.absoluteOutputDir,
                        prNumber: prNumber,
                        stats: PhaseStats(
                            artifactsProduced: allRules.count
                        )
                    )

                    continuation.yield(.running(phase: .tasks))
                    continuation.yield(.log(text: "Rules loaded: \(allRules.count)\n"))

                    // Phase 4: Create tasks
                    // Fetch the PR ref so git objects are available locally for blob hash lookups
                    try await gitOps.fetchBranch(remote: "origin", branch: "pull/\(prNum)/head", repoPath: self.config.repoPath)

                    let taskCreator = TaskCreatorService(ruleLoader: ruleLoader, gitOps: gitOps)
                    let tasks = try await taskCreator.createAndWriteTasks(
                        rules: allRules,
                        focusAreas: allFocusAreas,
                        outputDir: prOutputDir,
                        repoPath: self.config.repoPath,
                        commit: fullDiff.commitHash
                    )

                    // Write phase_result.json for phase 4 (tasks)
                    try PhaseResultWriter.writeSuccess(
                        phase: .tasks,
                        outputDir: config.absoluteOutputDir,
                        prNumber: prNumber,
                        stats: PhaseStats(
                            artifactsProduced: tasks.count
                        )
                    )

                    continuation.yield(.log(text: "Tasks created: \(tasks.count)\n"))

                    let output = RulesPhaseOutput(focusAreas: allFocusAreas, rules: allRules, tasks: tasks)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    public static func parseOutput(config: PRRadarConfig, prNumber: String) throws -> RulesPhaseOutput {
        let focusFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .focusAreas
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var allFocusAreas: [FocusArea] = []
        for file in focusFiles {
            let typeOutput: FocusAreaTypeOutput = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .focusAreas, filename: file
            )
            allFocusAreas.append(contentsOf: typeOutput.focusAreas)
        }

        let rules: [ReviewRule] = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .rules, filename: "all-rules.json"
        )

        let tasks: [EvaluationTaskOutput] = try PhaseOutputParser.parseAllPhaseFiles(
            config: config, prNumber: prNumber, phase: .tasks
        )

        return RulesPhaseOutput(focusAreas: allFocusAreas, rules: rules, tasks: tasks)
    }
}
