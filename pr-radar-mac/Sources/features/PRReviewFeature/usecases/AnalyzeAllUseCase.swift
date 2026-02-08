import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct AnalyzeAllOutput: Sendable {
    public let analyzedCount: Int
    public let failedCount: Int
}

public struct AnalyzeAllUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(
        since: String,
        rulesDir: String? = nil,
        minScore: String? = nil,
        repo: String? = nil,
        comment: Bool = false,
        limit: String? = nil,
        state: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<AnalyzeAllOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .pullRequest))

            Task {
                do {
                    let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath)

                    let limitNum = Int(limit ?? "100") ?? 100
                    let stateFilter = state ?? "merged"

                    continuation.yield(.log(text: "Fetching PRs since \(since) (state: \(stateFilter))...\n"))

                    let allPRs = try await gitHub.listPullRequests(
                        limit: limitNum,
                        state: stateFilter
                    )

                    let sinceDate = ISO8601DateFormatter().date(from: since + "T00:00:00Z")
                    let prs = allPRs.filter { pr in
                        guard let sinceDate else { return true }
                        guard let createdStr = pr.createdAt,
                              let createdDate = ISO8601DateFormatter().date(from: createdStr) else {
                            return true
                        }
                        return createdDate >= sinceDate
                    }

                    continuation.yield(.log(text: "Found \(prs.count) PRs to analyze\n"))

                    var analyzedCount = 0
                    var failedCount = 0

                    for pr in prs {
                        let prNumber = String(pr.number)
                        continuation.yield(.log(text: "\n--- PR #\(prNumber): \(pr.title) ---\n"))

                        let analyzeUseCase = AnalyzeUseCase(config: config)
                        var succeeded = false

                        for try await progress in analyzeUseCase.execute(
                            prNumber: prNumber,
                            rulesDir: rulesDir,
                            noDryRun: comment,
                            minScore: minScore
                        ) {
                            switch progress {
                            case .running: break
                            case .log(let text):
                                continuation.yield(.log(text: text))
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

                    let output = AnalyzeAllOutput(analyzedCount: analyzedCount, failedCount: failedCount)
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
