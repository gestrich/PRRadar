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

                    let bridgeClient = ClaudeBridgeClient(bridgeScriptPath: config.bridgeScriptPath)
                    let focusGenerator = FocusGeneratorService(bridgeClient: bridgeClient)

                    let focusResults = try await focusGenerator.generateAllFocusAreas(
                        hunks: fullDiff.hunks,
                        prNumber: prNum,
                        requestedTypes: [.method, .file]
                    )

                    let focusDir = "\(prOutputDir)/\(PRRadarPhase.focusAreas.rawValue)"
                    try FileManager.default.createDirectory(atPath: focusDir, withIntermediateDirectories: true)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                    var allFocusAreas: [FocusArea] = []
                    for (focusType, result) in focusResults {
                        allFocusAreas.append(contentsOf: result.focusAreas)
                        let typeOutput = FocusAreaTypeOutput(
                            prNumber: prNum,
                            generatedAt: ISO8601DateFormatter().string(from: Date()),
                            focusType: focusType.rawValue,
                            focusAreas: result.focusAreas,
                            totalHunksProcessed: result.totalHunksProcessed,
                            generationCostUsd: result.generationCostUsd
                        )
                        let data = try encoder.encode(typeOutput)
                        try data.write(to: URL(fileURLWithPath: "\(focusDir)/\(focusType.rawValue).json"))
                    }

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
                    let allRules = try await ruleLoader.loadAllRules(rulesDir: rulesPath, repoPath: rulesPath)

                    let rulesOutputDir = "\(prOutputDir)/\(PRRadarPhase.rules.rawValue)"
                    try FileManager.default.createDirectory(atPath: rulesOutputDir, withIntermediateDirectories: true)
                    let rulesData = try encoder.encode(allRules)
                    try rulesData.write(to: URL(fileURLWithPath: "\(rulesOutputDir)/all-rules.json"))

                    continuation.yield(.running(phase: .tasks))
                    continuation.yield(.log(text: "Rules loaded: \(allRules.count)\n"))

                    // Phase 4: Create tasks
                    let taskCreator = TaskCreatorService(ruleLoader: ruleLoader)
                    let tasks = try taskCreator.createAndWriteTasks(
                        rules: allRules,
                        focusAreas: allFocusAreas,
                        outputDir: prOutputDir
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
        ).filter { $0.hasSuffix(".json") }

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
