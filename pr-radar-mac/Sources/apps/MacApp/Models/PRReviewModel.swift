import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct ConfigContext {
    var config: RepoConfiguration
    var prs: [PRMetadata]
    var review: ReviewState?
}

struct ReviewState {
    var pr: PRMetadata
    var phaseStates: [PRRadarPhase: PRReviewModel.PhaseState]
    var diff: DiffPhaseSnapshot?
    var rules: RulesPhaseOutput?
    var evaluation: EvaluationPhaseOutput?
    var report: ReportPhaseOutput?
    var comments: CommentPhaseOutput?
    var selectedPhase: PRRadarPhase

    init(pr: PRMetadata) {
        self.pr = pr
        self.phaseStates = [:]
        self.selectedPhase = .pullRequest
    }
}

enum ModelState {
    case noConfig
    case hasConfig(ConfigContext)
}

@Observable
@MainActor
final class PRReviewModel {

    enum PhaseState: Sendable {
        case idle
        case running(logs: String)
        case completed(logs: String)
        case failed(error: String, logs: String)
    }

    private(set) var state: ModelState = .noConfig
    private(set) var settings: AppSettings

    private let venvBinPath: String
    private let environment: [String: String]
    private let settingsService: SettingsService

    init(venvBinPath: String, environment: [String: String], settingsService: SettingsService = SettingsService()) {
        self.venvBinPath = venvBinPath
        self.environment = environment
        self.settingsService = settingsService
        self.settings = settingsService.load()
        restoreSelections()
    }

    // MARK: - Mutation Helpers

    private func mutateConfigContext(_ transform: (inout ConfigContext) -> Void) {
        guard case .hasConfig(var ctx) = state else { return }
        transform(&ctx)
        state = .hasConfig(ctx)
    }

    private func mutateReview(_ transform: (inout ReviewState) -> Void) {
        mutateConfigContext { ctx in
            guard var review = ctx.review else { return }
            transform(&review)
            ctx.review = review
        }
    }

    // MARK: - Backward-Compatible Computed Properties

    var selectedConfiguration: RepoConfiguration? {
        guard case .hasConfig(let ctx) = state else { return nil }
        return ctx.config
    }

    var discoveredPRs: [PRMetadata] {
        guard case .hasConfig(let ctx) = state else { return [] }
        return ctx.prs
    }

    var selectedPR: PRMetadata? {
        get {
            guard case .hasConfig(let ctx) = state else { return nil }
            return ctx.review?.pr
        }
        set {
            if let pr = newValue {
                selectPR(pr)
            } else {
                mutateConfigContext { $0.review = nil }
                UserDefaults.standard.removeObject(forKey: "selectedPRNumber")
            }
        }
    }

    var selectedPhase: PRRadarPhase {
        get {
            guard case .hasConfig(let ctx) = state else { return .pullRequest }
            return ctx.review?.selectedPhase ?? .pullRequest
        }
        set {
            mutateReview { $0.selectedPhase = newValue }
        }
    }

    var phaseStates: [PRRadarPhase: PhaseState] {
        guard case .hasConfig(let ctx) = state else { return [:] }
        return ctx.review?.phaseStates ?? [:]
    }

    var fullDiff: GitDiff? {
        guard case .hasConfig(let ctx) = state else { return nil }
        return ctx.review?.diff?.fullDiff
    }

    var effectiveDiff: GitDiff? {
        guard case .hasConfig(let ctx) = state else { return nil }
        return ctx.review?.diff?.effectiveDiff
    }

    var moveReport: MoveReport? {
        guard case .hasConfig(let ctx) = state else { return nil }
        return ctx.review?.diff?.moveReport
    }

    var diffFiles: [String]? {
        guard case .hasConfig(let ctx) = state else { return nil }
        return ctx.review?.diff?.files
    }

    var rulesOutput: RulesPhaseOutput? {
        guard case .hasConfig(let ctx) = state else { return nil }
        return ctx.review?.rules
    }

    var evaluationOutput: EvaluationPhaseOutput? {
        guard case .hasConfig(let ctx) = state else { return nil }
        return ctx.review?.evaluation
    }

    var reportOutput: ReportPhaseOutput? {
        guard case .hasConfig(let ctx) = state else { return nil }
        return ctx.review?.report
    }

    var commentOutput: CommentPhaseOutput? {
        guard case .hasConfig(let ctx) = state else { return nil }
        return ctx.review?.comments
    }

    var prNumber: String {
        guard case .hasConfig(let ctx) = state, let review = ctx.review else { return "" }
        return String(review.pr.number)
    }

    // MARK: - Explicit State Transitions

    func selectPR(_ pr: PRMetadata) {
        mutateConfigContext { ctx in
            var review = ReviewState(pr: pr)
            let config = self.makeConfig(from: ctx.config)
            let snapshot = LoadExistingOutputsUseCase(config: config).execute(prNumber: String(pr.number))
            if let diff = snapshot.diff {
                review.diff = diff
                review.phaseStates[.pullRequest] = .completed(logs: "")
            }
            if let rules = snapshot.rules {
                review.rules = rules
                review.phaseStates[.focusAreas] = .completed(logs: "")
                review.phaseStates[.rules] = .completed(logs: "")
                review.phaseStates[.tasks] = .completed(logs: "")
            }
            if let evaluation = snapshot.evaluation {
                review.evaluation = evaluation
                review.phaseStates[.evaluations] = .completed(logs: "")
            }
            if let report = snapshot.report {
                review.report = report
                review.phaseStates[.report] = .completed(logs: "")
            }
            ctx.review = review
        }
        UserDefaults.standard.set(pr.number, forKey: "selectedPRNumber")
    }

    func selectConfiguration(_ config: RepoConfiguration) {
        let prs = PRDiscoveryService.discoverPRs(outputDir: config.outputDir)
        state = .hasConfig(ConfigContext(config: config, prs: prs, review: nil))
        persistSelectedConfigID()
    }

    func refreshPRList() {
        mutateConfigContext { ctx in
            ctx.prs = PRDiscoveryService.discoverPRs(outputDir: ctx.config.outputDir)
        }
    }

    private func restoreSelections() {
        let savedID = UserDefaults.standard.string(forKey: "selectedConfigID")
            .flatMap(UUID.init(uuidString:))
        if let savedID, let config = settings.configurations.first(where: { $0.id == savedID }) {
            selectConfiguration(config)
        } else if let config = settings.defaultConfiguration {
            selectConfiguration(config)
        }

        if selectedConfiguration != nil {
            let savedPR = UserDefaults.standard.integer(forKey: "selectedPRNumber")
            if savedPR != 0, let match = discoveredPRs.first(where: { $0.number == savedPR }) {
                selectPR(match)
            }
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
        guard selectedConfiguration != nil, !prNumber.isEmpty, !isAnyPhaseRunning else { return false }

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

    // MARK: - Configuration Management

    func addConfiguration(_ config: RepoConfiguration) {
        settingsService.addConfiguration(config, to: &settings)
        persistSettings()
        if settings.configurations.count == 1 {
            selectConfiguration(config)
        }
    }

    func removeConfiguration(id: UUID) {
        let wasSelected = selectedConfiguration?.id == id
        settingsService.removeConfiguration(id: id, from: &settings)
        persistSettings()
        if wasSelected {
            if let fallback = settings.defaultConfiguration {
                selectConfiguration(fallback)
            } else {
                state = .noConfig
            }
        }
    }

    func updateConfiguration(_ config: RepoConfiguration) {
        if let idx = settings.configurations.firstIndex(where: { $0.id == config.id }) {
            settings.configurations[idx] = config
            persistSettings()
        }
    }

    func setDefault(id: UUID) {
        settingsService.setDefault(id: id, in: &settings)
        persistSettings()
    }

    func startNewReview(prNumber: Int) async {
        guard selectedConfiguration != nil else { return }

        let fallback = PRMetadata.fallback(number: prNumber)
        if !discoveredPRs.contains(where: { $0.number == prNumber }) {
            mutateConfigContext { ctx in
                ctx.prs.insert(fallback, at: 0)
            }
        }
        if let match = discoveredPRs.first(where: { $0.number == prNumber }) {
            selectPR(match)
        }

        await runDiff()

        refreshPRList()
        if let updated = discoveredPRs.first(where: { $0.number == prNumber }) {
            selectPR(updated)
        }
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
        mutateReview { review in
            review.phaseStates[phase] = .idle
            switch phase {
            case .pullRequest:
                review.diff = nil
            case .focusAreas, .rules, .tasks:
                review.rules = nil
            case .evaluations:
                review.evaluation = nil
            case .report:
                review.report = nil
            }
        }
    }

    // MARK: - Phase Runners

    private func runDiff() async {
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        mutateReview { $0.phaseStates[.pullRequest] = .running(logs: "Running diff for PR #\(self.prNumber)...\n") }

        let useCase = FetchDiffUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .log(let text):
                    appendLog(text, to: .pullRequest)
                case .completed(let snapshot):
                    mutateReview { review in
                        review.diff = snapshot
                        let logs = self.runningLogs(for: .pullRequest)
                        review.phaseStates[.pullRequest] = .completed(logs: logs)
                    }
                case .failed(let error, let logs):
                    mutateReview { review in
                        let existingLogs = self.runningLogs(for: .pullRequest)
                        review.phaseStates[.pullRequest] = .failed(error: error, logs: existingLogs + logs)
                    }
                }
            }
        } catch {
            mutateReview { review in
                let logs = self.runningLogs(for: .pullRequest)
                review.phaseStates[.pullRequest] = .failed(error: error.localizedDescription, logs: logs)
            }
        }
    }

    private func runRules() async {
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        let rulesPhases: [PRRadarPhase] = [.focusAreas, .rules, .tasks]
        mutateReview { review in
            for phase in rulesPhases {
                review.phaseStates[phase] = .running(logs: "")
            }
        }

        let useCase = FetchRulesUseCase(config: config, environment: environment)
        let rulesDir = selected.rulesDir.isEmpty ? nil : selected.rulesDir

        do {
            for try await progress in useCase.execute(prNumber: prNumber, rulesDir: rulesDir) {
                switch progress {
                case .running(let phase):
                    mutateReview { $0.phaseStates[phase] = .running(logs: "Running \(phase.rawValue)...\n") }
                case .log(let text):
                    appendLog(text, to: .rules)
                case .completed(let output):
                    mutateReview { review in
                        review.rules = output
                        for phase in rulesPhases {
                            review.phaseStates[phase] = .completed(logs: "")
                        }
                    }
                case .failed(let error, let logs):
                    mutateReview { review in
                        for phase in rulesPhases {
                            review.phaseStates[phase] = .failed(error: error, logs: logs)
                        }
                    }
                }
            }
        } catch {
            mutateReview { review in
                for phase in rulesPhases {
                    review.phaseStates[phase] = .failed(error: error.localizedDescription, logs: "")
                }
            }
        }
    }

    private func runEvaluate() async {
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        mutateReview { $0.phaseStates[.evaluations] = .running(logs: "Running evaluations...\n") }

        let useCase = EvaluateUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .log(let text):
                    appendLog(text, to: .evaluations)
                case .completed(let output):
                    mutateReview { review in
                        review.evaluation = output
                        let logs = self.runningLogs(for: .evaluations)
                        review.phaseStates[.evaluations] = .completed(logs: logs)
                    }
                case .failed(let error, let logs):
                    mutateReview { $0.phaseStates[.evaluations] = .failed(error: error, logs: logs) }
                }
            }
        } catch {
            mutateReview { review in
                let logs = self.runningLogs(for: .evaluations)
                review.phaseStates[.evaluations] = .failed(error: error.localizedDescription, logs: logs)
            }
        }
    }

    private func runReport() async {
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        mutateReview { $0.phaseStates[.report] = .running(logs: "Generating report...\n") }

        let useCase = GenerateReportUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .log(let text):
                    appendLog(text, to: .report)
                case .completed(let output):
                    mutateReview { review in
                        review.report = output
                        let logs = self.runningLogs(for: .report)
                        review.phaseStates[.report] = .completed(logs: logs)
                    }
                case .failed(let error, let logs):
                    mutateReview { $0.phaseStates[.report] = .failed(error: error, logs: logs) }
                }
            }
        } catch {
            mutateReview { review in
                let logs = self.runningLogs(for: .report)
                review.phaseStates[.report] = .failed(error: error.localizedDescription, logs: logs)
            }
        }
    }

    func runComments(dryRun: Bool) async {
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        mutateReview { $0.phaseStates[.evaluations] = .running(logs: "Posting comments...\n") }

        let useCase = PostCommentsUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, dryRun: dryRun) {
                switch progress {
                case .running:
                    break
                case .log(let text):
                    appendLog(text, to: .evaluations)
                case .completed(let output):
                    mutateReview { review in
                        review.comments = output
                        let logs = self.runningLogs(for: .evaluations)
                        review.phaseStates[.evaluations] = .completed(logs: logs)
                    }
                case .failed(let error, let logs):
                    mutateReview { $0.phaseStates[.evaluations] = .failed(error: error, logs: logs) }
                }
            }
        } catch {
            mutateReview { $0.phaseStates[.evaluations] = .failed(error: error.localizedDescription, logs: "") }
        }
    }

    // MARK: - File Access

    func readFileFromRepo(_ relativePath: String) -> String? {
        guard let selected = selectedConfiguration else { return nil }
        let fullPath = "\(selected.repoPath)/\(relativePath)"
        return try? String(contentsOfFile: fullPath, encoding: .utf8)
    }

    // MARK: - Helpers

    private func makeConfig(from selected: RepoConfiguration) -> PRRadarConfig {
        PRRadarConfig(
            venvBinPath: venvBinPath,
            repoPath: selected.repoPath,
            outputDir: selected.outputDir
        )
    }

    private func runningLogs(for phase: PRRadarPhase) -> String {
        if case .running(let logs) = phaseStates[phase] { return logs }
        return ""
    }

    private func appendLog(_ text: String, to phase: PRRadarPhase) {
        mutateReview { review in
            let existing: String
            if case .running(let logs) = review.phaseStates[phase] {
                existing = logs
            } else {
                existing = ""
            }
            review.phaseStates[phase] = .running(logs: existing + text)
        }
    }

    private func persistSelectedConfigID() {
        if let id = selectedConfiguration?.id {
            UserDefaults.standard.set(id.uuidString, forKey: "selectedConfigID")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedConfigID")
        }
    }

    private func persistSettings() {
        try? settingsService.save(settings)
    }
}
