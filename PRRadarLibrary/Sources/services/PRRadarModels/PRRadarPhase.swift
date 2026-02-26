import Foundation

public enum PRRadarPhase: String, CaseIterable, Sendable {
    case metadata = "metadata"
    case diff = "diff"
    case prepare = "prepare"
    case analyze = "evaluate"
    case report = "report"

    /// The numeric phase number (1-5).
    public var phaseNumber: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    /// Whether this phase operates under a commit-scoped directory.
    /// Metadata is PR-scoped; all other phases are commit-scoped.
    public var isCommitScoped: Bool {
        self != .metadata
    }

    /// The phase that must complete before this one can run, or nil if none.
    /// Metadata and diff are independent roots; prepare → analyze → report is the linear chain.
    public var requiredPredecessor: PRRadarPhase? {
        switch self {
        case .metadata: nil
        case .diff: nil
        case .prepare: .diff
        case .analyze: .prepare
        case .report: .analyze
        }
    }

    /// Human-readable display name for the phase.
    public var displayName: String {
        switch self {
        case .metadata: "Metadata"
        case .diff: "Diff"
        case .prepare: "Prepare"
        case .analyze: "Analyze"
        case .report: "Report"
        }
    }
}
