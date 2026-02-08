import Foundation

/// Standard result file written at the end of every phase to indicate completion status.
///
/// This file serves as the source of truth for whether a phase completed successfully,
/// independent of what output artifacts were produced. Some phases may legitimately
/// produce zero output files (e.g., focus areas finding nothing, tasks creating no tasks).
///
/// File location: `<output_dir>/<pr_number>/<phase_name>/phase_result.json`
public struct PhaseResult: Codable, Sendable {
    /// The phase that completed
    public let phase: String
    
    /// Completion status
    public let status: PhaseStatus
    
    /// ISO8601 timestamp when the phase completed
    public let completedAt: String
    
    /// Optional error message if status is .failed
    public let errorMessage: String?
    
    /// Optional summary statistics specific to this phase
    public let stats: PhaseStats?
    
    public init(
        phase: String,
        status: PhaseStatus,
        completedAt: String = ISO8601DateFormatter().string(from: Date()),
        errorMessage: String? = nil,
        stats: PhaseStats? = nil
    ) {
        self.phase = phase
        self.status = status
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.stats = stats
    }
    
    enum CodingKeys: String, CodingKey {
        case phase
        case status
        case completedAt = "completed_at"
        case errorMessage = "error_message"
        case stats
    }
}

/// Phase completion status
public enum PhaseStatus: String, Codable, Sendable {
    /// Phase completed successfully (may have produced zero or more artifacts)
    case success
    
    /// Phase encountered an error and did not complete
    case failed
}

/// Optional statistics about phase execution
public struct PhaseStats: Codable, Sendable {
    /// Number of primary output artifacts produced (e.g., focus areas, tasks, evaluations)
    public let artifactsProduced: Int?
    
    /// Processing duration in milliseconds
    public let durationMs: Int?
    
    /// Cost in USD (for AI-powered phases)
    public let costUsd: Double?
    
    /// Any other phase-specific metadata
    public let metadata: [String: String]?
    
    public init(
        artifactsProduced: Int? = nil,
        durationMs: Int? = nil,
        costUsd: Double? = nil,
        metadata: [String: String]? = nil
    ) {
        self.artifactsProduced = artifactsProduced
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.metadata = metadata
    }
    
    enum CodingKeys: String, CodingKey {
        case artifactsProduced = "artifacts_produced"
        case durationMs = "duration_ms"
        case costUsd = "cost_usd"
        case metadata
    }
}
