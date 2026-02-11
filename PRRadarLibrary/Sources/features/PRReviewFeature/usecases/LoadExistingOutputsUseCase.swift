import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct PipelineSnapshot: Sendable {
    public let sync: SyncSnapshot?
    public let preparation: PrepareOutput?
    public let analysis: AnalysisOutput?
    public let report: ReportPhaseOutput?

    public init(sync: SyncSnapshot?, preparation: PrepareOutput?, analysis: AnalysisOutput?, report: ReportPhaseOutput?) {
        self.sync = sync
        self.preparation = preparation
        self.analysis = analysis
        self.report = report
    }
}

public struct LoadExistingOutputsUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(prNumber: String) -> PipelineSnapshot {
        let sync: SyncSnapshot? = {
            let snapshot = SyncPRUseCase.parseOutput(config: config, prNumber: prNumber)
            if snapshot.fullDiff != nil || snapshot.effectiveDiff != nil {
                return snapshot
            }
            return nil
        }()

        let preparation = try? PrepareUseCase.parseOutput(config: config, prNumber: prNumber)

        let analysis = try? AnalyzeUseCase.parseOutput(config: config, prNumber: prNumber)

        let report = try? GenerateReportUseCase.parseOutput(config: config, prNumber: prNumber)

        return PipelineSnapshot(sync: sync, preparation: preparation, analysis: analysis, report: report)
    }
}
