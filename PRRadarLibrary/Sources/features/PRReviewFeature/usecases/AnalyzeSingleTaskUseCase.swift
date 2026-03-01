import CLISDK
import ClaudeSDK
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct AnalyzeSingleTaskUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    /// Execute a single analysis task.
    ///
    /// Routes to `RegexAnalysisService` or `AnalysisService` based on whether the
    /// task's rule has a `violationRegex`. Callers that already have classified hunks
    /// loaded can pass them to avoid a redundant disk read.
    public func execute(
        task: RuleRequest,
        prNumber: Int,
        commitHash: String? = nil,
        classifiedHunks: [ClassifiedHunk]? = nil
    ) -> AsyncThrowingStream<TaskProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

                    let evalsDir = DataPathsService.phaseDirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .analyze,
                        commitHash: resolvedCommit
                    )

                    try DataPathsService.ensureDirectoryExists(at: evalsDir)

                    let result: RuleOutcome

                    if let pattern = task.rule.violationRegex {
                        let hunks = classifiedHunks ?? Self.loadClassifiedHunks(
                            config: config, prNumber: prNumber, commitHash: resolvedCommit
                        )
                        let focusedHunks = RegexAnalysisService.filterHunksForFocusArea(hunks, focusArea: task.focusArea)
                        result = RegexAnalysisService().analyzeTask(task, pattern: pattern, classifiedHunks: focusedHunks)
                    } else {
                        let resolver = CredentialResolver(settingsService: SettingsService(), githubAccount: config.githubAccount)
                        guard let anthropicKey = resolver.getAnthropicKey() else {
                            throw ClaudeAgentError.missingAPIKey
                        }
                        let agentEnv = ClaudeAgentEnvironment.build(anthropicAPIKey: anthropicKey)
                        let agentClient = ClaudeAgentClient(
                            pythonEnvironment: PythonEnvironment(agentScriptPath: config.agentScriptPath),
                            cliClient: CLIClient(),
                            environment: agentEnv
                        )
                        let analysisService = AnalysisService(agentClient: agentClient)

                        result = try await analysisService.analyzeTask(
                            task,
                            repoPath: config.repoPath,
                            transcriptDir: evalsDir,
                            onPrompt: { text, _ in
                                continuation.yield(.prompt(text: text))
                            },
                            onAIText: { text, _ in
                                continuation.yield(.output(text: text))
                            },
                            onAIToolUse: { name, _ in
                                continuation.yield(.toolUse(name: name))
                            }
                        )
                    }

                    // Write result to disk
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(result)
                    let resultPath = "\(evalsDir)/\(DataPathsService.dataFilePrefix)\(task.taskId).json"
                    try data.write(to: URL(fileURLWithPath: resultPath))

                    // Write task snapshot for cache
                    try AnalysisCacheService.writeTaskSnapshots(tasks: [task], evalsDir: evalsDir)

                    continuation.yield(.completed(result: result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private static func loadClassifiedHunks(
        config: RepositoryConfiguration,
        prNumber: Int,
        commitHash: String?
    ) -> [ClassifiedHunk] {
        (try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .diff,
            filename: DataPathsService.classifiedHunksFilename, commitHash: commitHash
        )) ?? []
    }
}
