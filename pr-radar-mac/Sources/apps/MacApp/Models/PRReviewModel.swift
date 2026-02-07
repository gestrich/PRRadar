import Foundation
import PRRadarCLIService
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
    private(set) var discoveredPRs: [PRMetadata] = []

    var selectedPR: PRMetadata? {
        didSet {
            resetAllPhases()
            loadExistingOutputs()
            if let number = selectedPR?.number {
                UserDefaults.standard.set(number, forKey: "selectedPRNumber")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedPRNumber")
            }
        }
    }

    // Typed phase outputs
    private(set) var diffFiles: [String]?
    private(set) var fullDiff: GitDiff?
    private(set) var effectiveDiff: GitDiff?
    private(set) var moveReport: MoveReport?
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
        if let pr = selectedPR {
            return String(pr.number)
        }
        return ""
    }

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

    private func restoreSelections() {
        if selectedConfiguration != nil {
            refreshPRList()
            let savedPR = UserDefaults.standard.integer(forKey: "selectedPRNumber")
            if savedPR != 0, let match = discoveredPRs.first(where: { $0.number == savedPR }) {
                selectedPR = match
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
        selectedPR = nil
        refreshPRList()
    }

    func refreshPRList() {
        guard let config = selectedConfiguration else {
            discoveredPRs = []
            return
        }
        discoveredPRs = PRDiscoveryService.discoverPRs(outputDir: config.outputDir)
    }

    func startNewReview(prNumber: Int) async {
        guard selectedConfiguration != nil else { return }

        let fallback = PRMetadata.fallback(number: prNumber)
        if !discoveredPRs.contains(where: { $0.number == prNumber }) {
            discoveredPRs.insert(fallback, at: 0)
        }
        selectedPR = discoveredPRs.first(where: { $0.number == prNumber })

        await runDiff()

        refreshPRList()
        if let updated = discoveredPRs.first(where: { $0.number == prNumber }) {
            selectedPR = updated
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
        phaseStates[phase] = .idle
        switch phase {
        case .pullRequest:
            diffFiles = nil
            fullDiff = nil
            effectiveDiff = nil
            moveReport = nil
        case .focusAreas, .rules, .tasks: rulesOutput = nil
        case .evaluations: evaluationOutput = nil
        case .report: reportOutput = nil
        }
    }

    func resetAllPhases() {
        phaseStates.removeAll()
        diffFiles = nil
        fullDiff = nil
        effectiveDiff = nil
        moveReport = nil
        rulesOutput = nil
        evaluationOutput = nil
        reportOutput = nil
        commentOutput = nil
    }

    // MARK: - Load Existing Outputs

    func loadExistingOutputs() {
        guard let selected = selectedConfiguration, selectedPR != nil else { return }
        let config = makeConfig(from: selected)

        // Phase 1: Diff outputs
        parseDiffOutputs(config: config)
        if fullDiff != nil || effectiveDiff != nil {
            phaseStates[.pullRequest] = .completed(logs: "")
        }

        // Phases 2-4: Focus areas, rules, tasks
        if let output = parseRulesOutputs(config: config) {
            rulesOutput = output
            phaseStates[.focusAreas] = .completed(logs: "")
            phaseStates[.rules] = .completed(logs: "")
            phaseStates[.tasks] = .completed(logs: "")
        }

        // Phase 5: Evaluations
        if let output = parseEvaluationOutputs(config: config) {
            evaluationOutput = output
            phaseStates[.evaluations] = .completed(logs: "")
        }

        // Phase 6: Report
        if let output = parseReportOutputs(config: config) {
            reportOutput = output
            phaseStates[.report] = .completed(logs: "")
        }
    }

    private func parseRulesOutputs(config: PRRadarConfig) -> RulesPhaseOutput? {
        let focusFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .focusAreas
        ).filter { $0.hasSuffix(".json") }

        var allFocusAreas: [FocusArea] = []
        for file in focusFiles {
            if let typeOutput: FocusAreaTypeOutput = try? PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .focusAreas, filename: file
            ) {
                allFocusAreas.append(contentsOf: typeOutput.focusAreas)
            }
        }

        guard let rules: [ReviewRule] = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .rules, filename: "all-rules.json"
        ) else { return nil }

        let tasks: [EvaluationTaskOutput] = (try? PhaseOutputParser.parseAllPhaseFiles(
            config: config, prNumber: prNumber, phase: .tasks
        )) ?? []

        guard !allFocusAreas.isEmpty || !rules.isEmpty else { return nil }

        return RulesPhaseOutput(focusAreas: allFocusAreas, rules: rules, tasks: tasks)
    }

    private func parseEvaluationOutputs(config: PRRadarConfig) -> EvaluationPhaseOutput? {
        guard let summary: EvaluationSummary = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .evaluations, filename: "summary.json"
        ) else { return nil }

        let evalFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .evaluations
        ).filter { $0.hasSuffix(".json") && $0 != "summary.json" }

        var evaluations: [RuleEvaluationResult] = []
        for file in evalFiles {
            if let evaluation: RuleEvaluationResult = try? PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .evaluations, filename: file
            ) {
                evaluations.append(evaluation)
            }
        }

        return EvaluationPhaseOutput(evaluations: evaluations, summary: summary)
    }

    private func parseReportOutputs(config: PRRadarConfig) -> ReportPhaseOutput? {
        guard let report: ReviewReport = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .report, filename: "summary.json"
        ) else { return nil }

        guard let markdown = try? PhaseOutputParser.readPhaseTextFile(
            config: config, prNumber: prNumber, phase: .report, filename: "summary.md"
        ) else { return nil }

        return ReportPhaseOutput(report: report, markdownContent: markdown)
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
                case .log(let text):
                    appendLog(text, to: .pullRequest)
                case .completed(let files):
                    diffFiles = files
                    parseDiffOutputs(config: config)
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

    private func parseDiffOutputs(config: PRRadarConfig) {
        // Parse full diff from the human-readable markdown file
        if let diffText = try? PhaseOutputParser.readPhaseTextFile(
            config: config, prNumber: prNumber, phase: .pullRequest, filename: "diff-parsed.md"
        ) {
            fullDiff = GitDiff.fromDiffContent(diffText)
        }

        // Parse effective diff from the human-readable markdown file
        if let effectiveText = try? PhaseOutputParser.readPhaseTextFile(
            config: config, prNumber: prNumber, phase: .pullRequest, filename: "effective-diff-parsed.md"
        ) {
            effectiveDiff = GitDiff.fromDiffContent(effectiveText)
        }

        // Parse move report
        if let report: MoveReport = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .pullRequest, filename: "effective-diff-moves.json"
        ) {
            moveReport = report
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
                case .log(let text):
                    appendLog(text, to: .rules)
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
                case .log(let text):
                    appendLog(text, to: .evaluations)
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
                case .log(let text):
                    appendLog(text, to: .report)
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
                case .log(let text):
                    appendLog(text, to: .evaluations)
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
        let existing = runningLogs(for: phase)
        phaseStates[phase] = .running(logs: existing + text)
    }

    private func persistSettings() {
        try? settingsService.save(settings)
    }
}
