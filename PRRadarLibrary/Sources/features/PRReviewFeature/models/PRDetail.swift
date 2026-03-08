import PRRadarConfigService
import PRRadarModels

public struct PRDetail: Sendable {
    public let commitHash: String?
    public let baseRefName: String?
    public let availableCommits: [String]
    public let phaseStatuses: [PRRadarPhase: PhaseStatus]
    public let syncSnapshot: SyncSnapshot?
    public let prDiff: PRDiff?
    public let storedEffectiveDiff: GitDiff?
    public let preparation: PrepareOutput?
    public let analysis: PRReviewResult?
    public let report: ReportPhaseOutput?
    public let postedComments: GitHubPullRequestComments?
    public let imageURLMap: [String: String]
    public let imageBaseDir: String?
    public let savedOutputs: [PRRadarPhase: [EvaluationOutput]]
    public let analysisSummary: PRReviewSummary?
    public let reviewComments: [ReviewComment]

    public init(
        commitHash: String?,
        baseRefName: String? = nil,
        availableCommits: [String],
        phaseStatuses: [PRRadarPhase: PhaseStatus],
        syncSnapshot: SyncSnapshot?,
        prDiff: PRDiff? = nil,
        storedEffectiveDiff: GitDiff? = nil,
        preparation: PrepareOutput?,
        analysis: PRReviewResult?,
        report: ReportPhaseOutput?,
        postedComments: GitHubPullRequestComments?,
        imageURLMap: [String: String],
        imageBaseDir: String?,
        savedOutputs: [PRRadarPhase: [EvaluationOutput]],
        analysisSummary: PRReviewSummary?,
        reviewComments: [ReviewComment]
    ) {
        self.commitHash = commitHash
        self.baseRefName = baseRefName
        self.availableCommits = availableCommits
        self.phaseStatuses = phaseStatuses
        self.syncSnapshot = syncSnapshot
        self.prDiff = prDiff
        self.storedEffectiveDiff = storedEffectiveDiff
        self.preparation = preparation
        self.analysis = analysis
        self.report = report
        self.postedComments = postedComments
        self.imageURLMap = imageURLMap
        self.imageBaseDir = imageBaseDir
        self.savedOutputs = savedOutputs
        self.analysisSummary = analysisSummary
        self.reviewComments = reviewComments
    }

    public var taskEvaluations: [TaskEvaluation]? {
        analysis?.taskEvaluations ?? preparation?.tasks.map { TaskEvaluation(request: $0, phase: .analyze) }
    }
}
