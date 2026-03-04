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
    /// Routes to `RegexAnalysisService`, `ScriptAnalysisService`, or `AnalysisService`
    /// based on the task's rule analysis type. Callers that already have an `AnnotatedDiff`
    /// loaded can pass it to avoid a redundant disk read.
    public func execute(
        task: RuleRequest,
        prNumber: Int,
        commitHash: String? = nil,
        annotatedDiff: AnnotatedDiff? = nil
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
                        let resolvedDiff = annotatedDiff ?? PhaseOutputParser.loadAnnotatedDiff(
                            config: config, prNumber: prNumber, commitHash: resolvedCommit
                        )
                        let hunks = resolvedDiff?.classifiedHunks ?? []
                        let focusedHunks = ClassifiedHunk.filterForFocusArea(hunks, focusArea: task.focusArea)
                        result = RegexAnalysisService().analyzeTask(task, pattern: pattern, classifiedHunks: focusedHunks)
                    } else if let scriptPath = task.rule.violationScript {
                        let resolvedDiff = annotatedDiff ?? PhaseOutputParser.loadAnnotatedDiff(
                            config: config, prNumber: prNumber, commitHash: resolvedCommit
                        )
                        let hunks = resolvedDiff?.classifiedHunks ?? []
                        let focusedHunks = ClassifiedHunk.filterForFocusArea(hunks, focusArea: task.focusArea)
                        result = ScriptAnalysisService().analyzeTask(task, scriptPath: scriptPath, repoPath: config.repoPath, classifiedHunks: focusedHunks)
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

}
