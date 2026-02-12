import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct RunPipelineOutput: Sendable {
    public let files: [PRRadarPhase: [String]]
    public let report: ReportPhaseOutput?

    public init(files: [PRRadarPhase: [String]], report: ReportPhaseOutput? = nil) {
        self.files = files
        self.report = report
    }
}

public struct RunPipelineUseCase: Sendable {

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
    ) -> AsyncThrowingStream<PhaseProgress<RunPipelineOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .diff))

            Task {
                do {
                    // Phase 1: Sync
                    continuation.yield(.log(text: "=== Phase 1: Syncing PR data ===\n"))
                    let diffUseCase = SyncPRUseCase(config: config)
                    var syncSnapshot: SyncSnapshot?
                    for try await progress in diffUseCase.execute(prNumber: prNumber) {
                        switch progress {
                        case .running: break
                        case .progress: break
                        case .log(let text):
                            continuation.yield(.log(text: text))
                        case .aiOutput: break
                        case .aiPrompt: break
                        case .aiToolUse: break
                        case .analysisResult: break
                        case .completed(let output):
                            syncSnapshot = output
                        case .failed(let error, let logs):
                            continuation.yield(.failed(error: "Diff phase failed: \(error)", logs: logs))
                            continuation.finish()
                            return
                        }
                    }
                    guard let syncOutput = syncSnapshot else {
                        continuation.yield(.failed(error: "Diff phase produced no output", logs: ""))
                        continuation.finish()
                        return
                    }
                    let commitHash = syncOutput.commitHash

                    // Phase 2: Prepare
                    continuation.yield(.running(phase: .prepare))
                    continuation.yield(.log(text: "\n=== Phase 2: Preparing evaluation tasks ===\n"))
                    let rulesUseCase = PrepareUseCase(config: config)
                    var rulesCompleted = false
                    for try await progress in rulesUseCase.execute(prNumber: prNumber, rulesDir: rulesDir, commitHash: commitHash) {
                        switch progress {
                        case .running(let phase):
                            continuation.yield(.running(phase: phase))
                        case .progress: break
                        case .log(let text):
                            continuation.yield(.log(text: text))
                        case .aiOutput(let text):
                            continuation.yield(.aiOutput(text: text))
                        case .aiPrompt(let text):
                            continuation.yield(.aiPrompt(text: text))
                        case .aiToolUse(let name):
                            continuation.yield(.aiToolUse(name: name))
                        case .analysisResult: break
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

                    // Phase 3: Analyze
                    continuation.yield(.running(phase: .analyze))
                    continuation.yield(.log(text: "\n=== Phase 3: Analyzing code ===\n"))
                    let evalUseCase = AnalyzeUseCase(config: config)
                    var evalCompleted = false
                    for try await progress in evalUseCase.execute(prNumber: prNumber, repoPath: repoPath, commitHash: commitHash) {
                        switch progress {
                        case .running: break
                        case .progress: break
                        case .log(let text):
                            continuation.yield(.log(text: text))
                        case .aiOutput(let text):
                            continuation.yield(.aiOutput(text: text))
                        case .aiPrompt(let text):
                            continuation.yield(.aiPrompt(text: text))
                        case .aiToolUse(let name):
                            continuation.yield(.aiToolUse(name: name))
                        case .analysisResult(let result):
                            continuation.yield(.analysisResult(result))
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

                    // Phase 4: Report
                    continuation.yield(.running(phase: .report))
                    continuation.yield(.log(text: "\n=== Phase 4: Report ===\n"))
                    let reportUseCase = GenerateReportUseCase(config: config)
                    var reportOutput: ReportPhaseOutput?
                    for try await progress in reportUseCase.execute(prNumber: prNumber, minScore: minScore, commitHash: commitHash) {
                        switch progress {
                        case .running: break
                        case .progress: break
                        case .log(let text):
                            continuation.yield(.log(text: text))
                        case .aiOutput: break
                        case .aiPrompt: break
                        case .aiToolUse: break
                        case .analysisResult: break
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
                        for try await progress in commentUseCase.execute(prNumber: prNumber, minScore: minScore, dryRun: false, commitHash: commitHash) {
                            switch progress {
                            case .running: break
                            case .progress: break
                            case .log(let text):
                                continuation.yield(.log(text: text))
                            case .aiOutput: break
                            case .aiPrompt: break
                            case .aiToolUse: break
                            case .analysisResult: break
                            case .completed: break
                            case .failed(let error, _):
                                continuation.yield(.log(text: "Comment posting failed: \(error)\n"))
                            }
                        }
                    }

                    // Collect output files per phase
                    var filesByPhase: [PRRadarPhase: [String]] = [:]
                    for phase in PRRadarPhase.allCases {
                        let files = OutputFileReader.files(in: config, prNumber: prNumber, phase: phase, commitHash: commitHash)
                        if !files.isEmpty {
                            filesByPhase[phase] = files
                        }
                    }

                    let output = RunPipelineOutput(files: filesByPhase, report: reportOutput)
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
