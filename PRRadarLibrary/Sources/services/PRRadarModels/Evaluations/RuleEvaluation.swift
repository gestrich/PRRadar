import Foundation

/// Result of evaluating a single rule against a focus area.
public struct RuleEvaluation: Codable, Sendable {
    public let violatesRule: Bool
    public let score: Int
    public let comment: String
    public let filePath: String
    public let lineNumber: Int?

    public init(violatesRule: Bool, score: Int, comment: String, filePath: String, lineNumber: Int?) {
        self.violatesRule = violatesRule
        self.score = score
        self.comment = comment
        self.filePath = filePath
        self.lineNumber = lineNumber
    }
}
