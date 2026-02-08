import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

@Observable
@MainActor
final class PRModel: Identifiable {

    enum AnalysisState {
        case loading
        case loaded(violationCount: Int, evaluatedAt: String)
        case unavailable
    }

    let metadata: PRMetadata
    let config: PRRadarConfig

    nonisolated var id: Int { metadata.id }

    private(set) var analysisState: AnalysisState = .loading

    init(metadata: PRMetadata, config: PRRadarConfig) {
        self.metadata = metadata
        self.config = config
        Task { await loadAnalysisSummary() }
    }

    private func loadAnalysisSummary() async {
        do {
            let summary: EvaluationSummary = try PhaseOutputParser.parsePhaseOutput(
                config: config,
                prNumber: String(metadata.number),
                phase: .evaluations,
                filename: "summary.json"
            )
            analysisState = .loaded(
                violationCount: summary.violationsFound,
                evaluatedAt: summary.evaluatedAt
            )
        } catch {
            analysisState = .unavailable
        }
    }
}
