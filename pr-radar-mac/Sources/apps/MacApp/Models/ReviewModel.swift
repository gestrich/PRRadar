import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

@Observable
@MainActor
final class ReviewModel {

    enum PhaseState: Sendable {
        case idle
        case running(logs: String)
        case completed(logs: String)
        case failed(error: String, logs: String)
    }

    let pr: PRMetadata
    let config: PRRadarConfig
    let repoConfig: RepoConfiguration
    private let environment: [String: String]

    private(set) var phaseStates: [PRRadarPhase: PhaseState] = [:]
    var selectedPhase: PRRadarPhase = .pullRequest

    private(set) var diff: DiffPhaseSnapshot?
    private(set) var rules: RulesPhaseOutput?
    private(set) var evaluation: EvaluationPhaseOutput?
    private(set) var report: ReportPhaseOutput?
    private(set) var comments: CommentPhaseOutput?

    private(set) var submittingCommentIds: Set<String> = []
    private(set) var submittedCommentIds: Set<String> = []

    init(pr: PRMetadata, config: PRRadarConfig, repoConfig: RepoConfiguration, environment: [String: String]) {
        self.pr = pr
        self.config = config
        self.repoConfig = repoConfig
        self.environment = environment
    }

    // MARK: - Computed Properties

    var prNumber: String {
        String(pr.number)
    }

    var fullDiff: GitDiff? {
        diff?.fullDiff
    }

    var effectiveDiff: GitDiff? {
        diff?.effectiveDiff
    }

    var moveReport: MoveReport? {
        diff?.moveReport
    }

    var diffFiles: [String]? {
        diff?.files
    }

    var rulesOutput: RulesPhaseOutput? {
        rules
    }

    var evaluationOutput: EvaluationPhaseOutput? {
        evaluation
    }

    var reportOutput: ReportPhaseOutput? {
        report
    }

    var commentOutput: CommentPhaseOutput? {
        comments
    }

    // MARK: - Load Existing Outputs

    func loadExistingOutputs() {
        let snapshot = LoadExistingOutputsUseCase(config: config).execute(prNumber: prNumber)
        if let diff = snapshot.diff {
            self.diff = diff
            phaseStates[.pullRequest] = .completed(logs: "")
        }
        if let rules = snapshot.rules {
            self.rules = rules
            phaseStates[.focusAreas] = .completed(logs: "")
            phaseStates[.rules] = .completed(logs: "")
            phaseStates[.tasks] = .completed(logs: "")
        }
        if let evaluation = snapshot.evaluation {
            self.evaluation = evaluation
            phaseStates[.evaluations] = .completed(logs: "")
        }
        if let report = snapshot.report {
            self.report = report
            phaseStates[.report] = .completed(logs: "")
        }
    }

    // MARK: - State Queries

    func stateFor(_ phase: PRRadarPhase) -> PhaseState {
        phaseStates[phase] ?? .idle
    }

    var isAnyPhaseRunning: Bool {
        phaseStates.values.contains { if case .running = $0 { return true } else { return false } }
    }

    func canRunPhase(_ phase: PRRadarPhase) -> Bool {
        guard !isAnyPhaseRunning else { return false }

        switch phase {
        case .pullRequest:
            return true
        case .focusAreas, .rules, .tasks:
            return isPhaseCompleted(.pullRequest)
        case .evaluations:
            return isPhaseCompleted(.tasks)
        case .report:
            return isPhaseCompleted(.evaluations)
        }
    }

    func isPhaseCompleted(_ phase: PRRadarPhase) -> Bool {
        if case .completed = stateFor(phase) { return true }
        return false
    }

    // MARK: - Phase Execution

    func runPhase(_ phase: PRRadarPhase) async {
        switch phase {
        case .pullRequest: await runDiff()
        case .focusAreas, .rules, .tasks: await runRules()
        case .evaluations: await runEvaluate()
        case .report: await runReport()
        }
    }

    func runAllPhases() async {
        let phases: [PRRadarPhase] = [.pullRequest, .rules, .evaluations, .report]
        for phase in phases {
            guard canRunPhase(phase) else { break }
            await runPhase(phase)
            if case .failed = stateFor(phase) { break }
        }
    }

    func resetPhase(_ phase: PRRadarPhase) {
        phaseStates[phase] = .idle
        switch phase {
        case .pullRequest:
            diff = nil
        case .focusAreas, .rules, .tasks:
            rules = nil
        case .evaluations:
            evaluation = nil
        case .report:
            report = nil
        }
    }

    // MARK: - Phase Runners

    func runDiff() async {
        phaseStates[.pullRequest] = .running(logs: "Running diff for PR #\(prNumber)...\n")

        let useCase = FetchDiffUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .log(let text):
                    appendLog(text, to: .pullRequest)
                case .completed(let snapshot):
                    diff = snapshot
                    let logs = runningLogs(for: .pullRequest)
                    phaseStates[.pullRequest] = .completed(logs: logs)
                case .failed(let error, let logs):
                    let existingLogs = runningLogs(for: .pullRequest)
                    phaseStates[.pullRequest] = .failed(error: error, logs: existingLogs + logs)
                }
            }
        } catch {
            let logs = runningLogs(for: .pullRequest)
            phaseStates[.pullRequest] = .failed(error: error.localizedDescription, logs: logs)
        }
    }

    private func runRules() async {
        let rulesPhases: [PRRadarPhase] = [.focusAreas, .rules, .tasks]
        for phase in rulesPhases {
            phaseStates[phase] = .running(logs: "")
        }

        let useCase = FetchRulesUseCase(config: config, environment: environment)
        let rulesDir = repoConfig.rulesDir.isEmpty ? nil : repoConfig.rulesDir

        do {
            for try await progress in useCase.execute(prNumber: prNumber, rulesDir: rulesDir) {
                switch progress {
                case .running(let phase):
                    phaseStates[phase] = .running(logs: "Running \(phase.rawValue)...\n")
                case .log(let text):
                    appendLog(text, to: .rules)
                case .completed(let output):
                    rules = output
                    for phase in rulesPhases {
                        phaseStates[phase] = .completed(logs: "")
                    }
                case .failed(let error, let logs):
                    for phase in rulesPhases {
                        phaseStates[phase] = .failed(error: error, logs: logs)
                    }
                }
            }
        } catch {
            for phase in rulesPhases {
                phaseStates[phase] = .failed(error: error.localizedDescription, logs: "")
            }
        }
    }

    private func runEvaluate() async {
        phaseStates[.evaluations] = .running(logs: "Running evaluations...\n")

        let useCase = EvaluateUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .log(let text):
                    appendLog(text, to: .evaluations)
                case .completed(let output):
                    evaluation = output
                    let logs = runningLogs(for: .evaluations)
                    phaseStates[.evaluations] = .completed(logs: logs)
                case .failed(let error, let logs):
                    phaseStates[.evaluations] = .failed(error: error, logs: logs)
                }
            }
        } catch {
            let logs = runningLogs(for: .evaluations)
            phaseStates[.evaluations] = .failed(error: error.localizedDescription, logs: logs)
        }
    }

    private func runReport() async {
        phaseStates[.report] = .running(logs: "Generating report...\n")

        let useCase = GenerateReportUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .log(let text):
                    appendLog(text, to: .report)
                case .completed(let output):
                    report = output
                    let logs = runningLogs(for: .report)
                    phaseStates[.report] = .completed(logs: logs)
                case .failed(let error, let logs):
                    phaseStates[.report] = .failed(error: error, logs: logs)
                }
            }
        } catch {
            let logs = runningLogs(for: .report)
            phaseStates[.report] = .failed(error: error.localizedDescription, logs: logs)
        }
    }

    func runComments(dryRun: Bool) async {
        phaseStates[.evaluations] = .running(logs: "Posting comments...\n")

        let useCase = PostCommentsUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, dryRun: dryRun) {
                switch progress {
                case .running:
                    break
                case .log(let text):
                    appendLog(text, to: .evaluations)
                case .completed(let output):
                    comments = output
                    let logs = runningLogs(for: .evaluations)
                    phaseStates[.evaluations] = .completed(logs: logs)
                case .failed(let error, let logs):
                    phaseStates[.evaluations] = .failed(error: error, logs: logs)
                }
            }
        } catch {
            phaseStates[.evaluations] = .failed(error: error.localizedDescription, logs: "")
        }
    }

    // MARK: - Single Comment Submission

    func submitSingleComment(_ evaluation: RuleEvaluationResult) async {
        guard let fullDiff else { return }
        let commitSHA = fullDiff.commitHash
        guard let repoSlug = PRDiscoveryService.repoSlug(fromRepoPath: repoConfig.repoPath) else { return }

        submittingCommentIds.insert(evaluation.taskId)

        let commentBody = "**\(evaluation.ruleName)** (Score: \(evaluation.evaluation.score)/10)\n\n\(evaluation.evaluation.comment)"

        let useCase = PostSingleCommentUseCase(environment: environment)

        do {
            let success = try await useCase.execute(
                repoSlug: repoSlug,
                prNumber: prNumber,
                filePath: evaluation.evaluation.filePath,
                lineNumber: evaluation.evaluation.lineNumber,
                commitSHA: commitSHA,
                commentBody: commentBody
            )

            submittingCommentIds.remove(evaluation.taskId)
            if success {
                submittedCommentIds.insert(evaluation.taskId)
            }
        } catch {
            submittingCommentIds.remove(evaluation.taskId)
        }
    }

    // MARK: - File Access

    func readFileFromRepo(_ relativePath: String) -> String? {
        let fullPath = "\(repoConfig.repoPath)/\(relativePath)"
        return try? String(contentsOfFile: fullPath, encoding: .utf8)
    }

    // MARK: - Helpers

    private func runningLogs(for phase: PRRadarPhase) -> String {
        if case .running(let logs) = phaseStates[phase] { return logs }
        return ""
    }

    private func appendLog(_ text: String, to phase: PRRadarPhase) {
        let existing: String
        if case .running(let logs) = phaseStates[phase] {
            existing = logs
        } else {
            existing = ""
        }
        phaseStates[phase] = .running(logs: existing + text)
    }
}
