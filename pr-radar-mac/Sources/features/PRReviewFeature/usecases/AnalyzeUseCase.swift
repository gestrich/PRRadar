import CLISDK
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct AnalyzePhaseOutput: Sendable {
    public let files: [PRRadarPhase: [String]]
    public let report: ReportPhaseOutput?

    public init(files: [PRRadarPhase: [String]], report: ReportPhaseOutput? = nil) {
        self.files = files
        self.report = report
    }
}

public struct AnalyzeUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(
        prNumber: String,
        rulesDir: String? = nil,
        repoPath: String? = nil,
        noDryRun: Bool = false,
        minScore: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<AnalyzePhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .pullRequest))

            Task {
                do {
                    // Phase 1: Diff
                    continuation.yield(.log(text: "=== Phase 1: Fetching PR diff ===\n"))
                    let diffUseCase = FetchDiffUseCase(config: config)
                    var diffCompleted = false
                    for try await progress in diffUseCase.execute(prNumber: prNumber) {
                        switch progress {
                        case .running: break
                        case .log(let text):
                            continuation.yield(.log(text: text))
                        case .completed:
                            diffCompleted = true
                        case .failed(let error, let logs):
                            continuation.yield(.failed(error: "Diff phase failed: \(error)", logs: logs))
                            continuation.finish()
                            return
                        }
                    }
                    guard diffCompleted else {
                        continuation.yield(.failed(error: "Diff phase produced no output", logs: ""))
                        continuation.finish()
                        return
                    }

                    // Phase 2-4: Rules
                    continuation.yield(.running(phase: .focusAreas))
                    continuation.yield(.log(text: "\n=== Phase 2-4: Focus areas, rules, and tasks ===\n"))
                    let rulesUseCase = FetchRulesUseCase(config: config)
                    var rulesCompleted = false
                    for try await progress in rulesUseCase.execute(prNumber: prNumber, rulesDir: rulesDir) {
                        switch progress {
                        case .running(let phase):
                            continuation.yield(.running(phase: phase))
                        case .log(let text):
                            continuation.yield(.log(text: text))
                        case .completed:
                            rulesCompleted = true
                        case .failed(let error, let logs):
                            continuation.yield(.failed(error: "Rules phase failed: \(error)", logs: logs))
                            continuation.finish()
                            return
                        }
                    }
                    guard rulesCompleted else {
                        continuation.yield(.failed(error: "Rules phase produced no output", logs: ""))
                        continuation.finish()
                        return
                    }

                    // Phase 5: Evaluate
                    continuation.yield(.running(phase: .evaluations))
                    continuation.yield(.log(text: "\n=== Phase 5: Evaluations ===\n"))
                    let evalUseCase = EvaluateUseCase(config: config)
                    var evalCompleted = false
                    for try await progress in evalUseCase.execute(prNumber: prNumber, repoPath: repoPath) {
                        switch progress {
                        case .running: break
                        case .log(let text):
                            continuation.yield(.log(text: text))
                        case .completed:
                            evalCompleted = true
                        case .failed(let error, let logs):
                            continuation.yield(.failed(error: "Evaluation phase failed: \(error)", logs: logs))
                            continuation.finish()
                            return
                        }
                    }
                    guard evalCompleted else {
                        continuation.yield(.failed(error: "Evaluation phase produced no output", logs: ""))
                        continuation.finish()
                        return
                    }

                    // Phase 6: Report
                    continuation.yield(.running(phase: .report))
                    continuation.yield(.log(text: "\n=== Phase 6: Report ===\n"))
                    let reportUseCase = GenerateReportUseCase(config: config)
                    var reportOutput: ReportPhaseOutput?
                    for try await progress in reportUseCase.execute(prNumber: prNumber, minScore: minScore) {
                        switch progress {
                        case .running: break
                        case .log(let text):
                            continuation.yield(.log(text: text))
                        case .completed(let output):
                            reportOutput = output
                        case .failed(let error, let logs):
                            continuation.yield(.failed(error: "Report phase failed: \(error)", logs: logs))
                            continuation.finish()
                            return
                        }
                    }

                    // Optional: Post comments
                    if noDryRun {
                        continuation.yield(.log(text: "\n=== Posting comments ===\n"))
                        let commentUseCase = PostCommentsUseCase(config: config)
                        for try await progress in commentUseCase.execute(prNumber: prNumber, minScore: minScore, dryRun: false) {
                            switch progress {
                            case .running: break
                            case .log(let text):
                                continuation.yield(.log(text: text))
                            case .completed: break
                            case .failed(let error, _):
                                continuation.yield(.log(text: "Comment posting failed: \(error)\n"))
                            }
                        }
                    }

                    // Collect output files per phase
                    var filesByPhase: [PRRadarPhase: [String]] = [:]
                    for phase in PRRadarPhase.allCases {
                        let files = OutputFileReader.files(in: config, prNumber: prNumber, phase: phase)
                        if !files.isEmpty {
                            filesByPhase[phase] = files
                        }
                    }

                    let output = AnalyzePhaseOutput(files: filesByPhase, report: reportOutput)
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
