import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

@Observable
@MainActor
final class PRReviewModel {

    enum PhaseState: Sendable {
        case idle
        case running(logs: String)
        case completed(logs: String)
        case failed(error: String, logs: String)
    }

    private(set) var phaseStates: [PRRadarPhase: PhaseState] = [:]
    private(set) var settings: AppSettings

    // Typed phase outputs
    private(set) var diffFiles: [String]?
    private(set) var rulesOutput: RulesPhaseOutput?
    private(set) var evaluationOutput: EvaluationPhaseOutput?
    private(set) var reportOutput: ReportPhaseOutput?
    private(set) var commentOutput: CommentPhaseOutput?

    var selectedPhase: PRRadarPhase = .pullRequest

    var selectedConfiguration: RepoConfiguration? {
        get {
            let savedID = UserDefaults.standard.string(forKey: "selectedConfigID")
                .flatMap(UUID.init(uuidString:))
            if let savedID, let config = settings.configurations.first(where: { $0.id == savedID }) {
                return config
            }
            return settings.defaultConfiguration
        }
        set {
            if let id = newValue?.id {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedConfigID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedConfigID")
            }
        }
    }

    var prNumber: String {
        get { access(keyPath: \.prNumber); return UserDefaults.standard.string(forKey: "prNumber") ?? "" }
        set { withMutation(keyPath: \.prNumber) { UserDefaults.standard.set(newValue, forKey: "prNumber") } }
    }

    private let venvBinPath: String
    private let environment: [String: String]
    private let settingsService: SettingsService

    init(venvBinPath: String, environment: [String: String], settingsService: SettingsService = SettingsService()) {
        self.venvBinPath = venvBinPath
        self.environment = environment
        self.settingsService = settingsService
        self.settings = settingsService.load()
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
            selectedConfiguration = config
        }
    }

    func removeConfiguration(id: UUID) {
        let wasSelected = selectedConfiguration?.id == id
        settingsService.removeConfiguration(id: id, from: &settings)
        persistSettings()
        if wasSelected {
            selectedConfiguration = settings.defaultConfiguration
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

    func selectConfiguration(_ config: RepoConfiguration) {
        selectedConfiguration = config
        resetAllPhases()
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
        case .pullRequest: diffFiles = nil
        case .focusAreas, .rules, .tasks: rulesOutput = nil
        case .evaluations: evaluationOutput = nil
        case .report: reportOutput = nil
        }
    }

    func resetAllPhases() {
        phaseStates.removeAll()
        diffFiles = nil
        rulesOutput = nil
        evaluationOutput = nil
        reportOutput = nil
        commentOutput = nil
    }

    // MARK: - Phase Runners

    private func runDiff() async {
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        phaseStates[.pullRequest] = .running(logs: "Running diff for PR #\(prNumber)...\n")

        let useCase = FetchDiffUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .completed(let files):
                    diffFiles = files
                    let logs = runningLogs(for: .pullRequest)
                    phaseStates[.pullRequest] = .completed(logs: logs)
                case .failed(let error):
                    let logs = runningLogs(for: .pullRequest)
                    phaseStates[.pullRequest] = .failed(error: error, logs: logs)
                }
            }
        } catch {
            let logs = runningLogs(for: .pullRequest)
            phaseStates[.pullRequest] = .failed(error: error.localizedDescription, logs: logs)
        }
    }

    private func runRules() async {
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        let rulesPhases: [PRRadarPhase] = [.focusAreas, .rules, .tasks]
        for phase in rulesPhases {
            phaseStates[phase] = .running(logs: "")
        }

        let useCase = FetchRulesUseCase(config: config, environment: environment)
        let rulesDir = selected.rulesDir.isEmpty ? nil : selected.rulesDir

        do {
            for try await progress in useCase.execute(prNumber: prNumber, rulesDir: rulesDir) {
                switch progress {
                case .running(let phase):
                    phaseStates[phase] = .running(logs: "Running \(phase.rawValue)...\n")
                case .completed(let output):
                    rulesOutput = output
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
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        phaseStates[.evaluations] = .running(logs: "Running evaluations...\n")

        let useCase = EvaluateUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .completed(let output):
                    evaluationOutput = output
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
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        phaseStates[.report] = .running(logs: "Generating report...\n")

        let useCase = GenerateReportUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .completed(let output):
                    reportOutput = output
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
        guard let selected = selectedConfiguration else { return }

        let config = makeConfig(from: selected)
        phaseStates[.evaluations] = .running(logs: "Posting comments...\n")

        let useCase = PostCommentsUseCase(config: config, environment: environment)

        do {
            for try await progress in useCase.execute(prNumber: prNumber, dryRun: dryRun) {
                switch progress {
                case .running:
                    break
                case .completed(let output):
                    commentOutput = output
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

    private func persistSettings() {
        try? settingsService.save(settings)
    }
}
