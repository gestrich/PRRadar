import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct RunAllOutput: Sendable {
    public let analyzedCount: Int
    public let failedCount: Int
}

public struct RunAllUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(
        since: String,
        rulesDir: String,
        minScore: String? = nil,
        repo: String? = nil,
        comment: Bool = false,
        limit: String? = nil,
        state: PRState? = nil
    ) -> AsyncThrowingStream<PhaseProgress<RunAllOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .diff))

            Task {
                do {
                    let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)

                    let limitNum = Int(limit ?? "10000") ?? 10000
                    let sinceDate = ISO8601DateFormatter().date(from: since + "T00:00:00Z")

                    continuation.yield(.log(text: "Fetching PRs since \(since) (state: \(state?.displayName ?? "all"))...\n"))

                    let prs = try await gitHub.listPullRequests(
                        limit: limitNum,
                        state: state,
                        since: sinceDate
                    )

                    continuation.yield(.log(text: "Found \(prs.count) PRs to analyze\n"))

                    var analyzedCount = 0
                    var failedCount = 0
                    let totalCount = prs.count

                    for (index, pr) in prs.enumerated() {
                        let prNumber = pr.number
                        let current = index + 1
                        continuation.yield(.progress(current: current, total: totalCount))
                        continuation.yield(.log(text: "\n[\(current)/\(totalCount)] PR #\(prNumber): \(pr.title)\n"))

                        let analyzeUseCase = RunPipelineUseCase(config: config)
                        var succeeded = false

                        for try await progress in analyzeUseCase.execute(
                            prNumber: prNumber,
                            rulesDir: rulesDir,
                            noDryRun: comment,
                            minScore: minScore
                        ) {
                            switch progress {
                            case .running: break
                            case .progress: break
                            case .log(let text):
                                continuation.yield(.log(text: text))
                            case .prepareOutput(let text):
                                continuation.yield(.prepareOutput(text: text))
                            case .prepareToolUse(let name):
                                continuation.yield(.prepareToolUse(name: name))
                            case .taskEvent(let task, let event):
                                continuation.yield(.taskEvent(task: task, event: event))
                            case .completed:
                                succeeded = true
                            case .failed(let error, _):
                                continuation.yield(.log(text: "  Failed: \(error)\n"))
                            }
                        }

                        if succeeded {
                            analyzedCount += 1
                        } else {
                            failedCount += 1
                        }
                    }

                    continuation.yield(.log(text: "\nAnalyze-all complete: \(analyzedCount) succeeded, \(failedCount) failed\n"))

                    let output = RunAllOutput(analyzedCount: analyzedCount, failedCount: failedCount)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }
}
