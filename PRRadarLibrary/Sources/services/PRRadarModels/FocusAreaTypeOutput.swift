import Foundation

/// Container for a per-type focus areas JSON file (e.g. method.json, file.json).
/// Wraps the focus areas with metadata written by the Python pipeline.
public struct FocusAreaTypeOutput: Codable, Sendable {
    public let prNumber: Int
    public let generatedAt: String
    public let focusType: String
    public let focusAreas: [FocusArea]
    public let totalHunksProcessed: Int
    public let generationCostUsd: Double

    public init(
        prNumber: Int,
        generatedAt: String,
        focusType: String,
        focusAreas: [FocusArea],
        totalHunksProcessed: Int,
        generationCostUsd: Double
    ) {
        self.prNumber = prNumber
        self.generatedAt = generatedAt
        self.focusType = focusType
        self.focusAreas = focusAreas
        self.totalHunksProcessed = totalHunksProcessed
        self.generationCostUsd = generationCostUsd
    }

    enum CodingKeys: String, CodingKey {
        case prNumber = "pr_number"
        case generatedAt = "generated_at"
        case focusType = "focus_type"
        case focusAreas = "focus_areas"
        case totalHunksProcessed = "total_hunks_processed"
        case generationCostUsd = "generation_cost_usd"
    }
}
