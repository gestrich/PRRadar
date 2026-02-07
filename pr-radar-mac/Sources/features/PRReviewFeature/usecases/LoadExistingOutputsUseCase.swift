import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct PipelineSnapshot: Sendable {
    public let diff: DiffPhaseSnapshot?
    public let rules: RulesPhaseOutput?
    public let evaluation: EvaluationPhaseOutput?
    public let report: ReportPhaseOutput?

    public init(diff: DiffPhaseSnapshot?, rules: RulesPhaseOutput?, evaluation: EvaluationPhaseOutput?, report: ReportPhaseOutput?) {
        self.diff = diff
        self.rules = rules
        self.evaluation = evaluation
        self.report = report
    }
}

public struct LoadExistingOutputsUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(prNumber: String) -> PipelineSnapshot {
        let diff: DiffPhaseSnapshot? = {
            let snapshot = FetchDiffUseCase.parseOutput(config: config, prNumber: prNumber)
            if snapshot.fullDiff != nil || snapshot.effectiveDiff != nil {
                return snapshot
            }
            return nil
        }()

        let rules = try? FetchRulesUseCase.parseOutput(config: config, prNumber: prNumber)

        let evaluation = try? EvaluateUseCase.parseOutput(config: config, prNumber: prNumber)

        let report = try? GenerateReportUseCase.parseOutput(config: config, prNumber: prNumber)

        return PipelineSnapshot(diff: diff, rules: rules, evaluation: evaluation, report: report)
    }
}
