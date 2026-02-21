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

    public func execute(
        task: AnalysisTaskOutput,
        prNumber: Int,
        commitHash: String? = nil
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

                    let result = try await analysisService.analyzeTask(
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
