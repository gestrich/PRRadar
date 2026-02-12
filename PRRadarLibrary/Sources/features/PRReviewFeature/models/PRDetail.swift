import PRRadarConfigService
import PRRadarModels

public struct PRDetail: Sendable {
    public let commitHash: String?
    public let availableCommits: [String]
    public let phaseStatuses: [PRRadarPhase: PhaseStatus]
    public let syncSnapshot: SyncSnapshot?
    public let preparation: PrepareOutput?
    public let analysis: AnalysisOutput?
    public let report: ReportPhaseOutput?
    public let postedComments: GitHubPullRequestComments?
    public let imageURLMap: [String: String]
    public let imageBaseDir: String?
    public let savedTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]]
    public let analysisSummary: AnalysisSummary?

    public init(
        commitHash: String?,
        availableCommits: [String],
        phaseStatuses: [PRRadarPhase: PhaseStatus],
        syncSnapshot: SyncSnapshot?,
        preparation: PrepareOutput?,
        analysis: AnalysisOutput?,
        report: ReportPhaseOutput?,
        postedComments: GitHubPullRequestComments?,
        imageURLMap: [String: String],
        imageBaseDir: String?,
        savedTranscripts: [PRRadarPhase: [ClaudeAgentTranscript]],
        analysisSummary: AnalysisSummary?
    ) {
        self.commitHash = commitHash
        self.availableCommits = availableCommits
        self.phaseStatuses = phaseStatuses
        self.syncSnapshot = syncSnapshot
        self.preparation = preparation
        self.analysis = analysis
        self.report = report
        self.postedComments = postedComments
        self.imageURLMap = imageURLMap
        self.imageBaseDir = imageBaseDir
        self.savedTranscripts = savedTranscripts
        self.analysisSummary = analysisSummary
    }
}
