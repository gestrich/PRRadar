import Foundation

// MARK: - Phase 1: Diff Output Models

/// A single code move detected by the effective diff algorithm.
public struct MoveDetail: Codable, Sendable, Equatable {
    public let sourceFile: String
    public let targetFile: String
    public let sourceLines: [Int]
    public let targetLines: [Int]
    public let matchedLines: Int
    public let score: Double
    public let effectiveDiffLines: Int

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case targetFile = "target_file"
        case sourceLines = "source_lines"
        case targetLines = "target_lines"
        case matchedLines = "matched_lines"
        case score
        case effectiveDiffLines = "effective_diff_lines"
    }
}

/// Move detection report parsed from effective-diff-moves.json.
public struct MoveReport: Codable, Sendable {
    public let movesDetected: Int
    public let totalLinesMoved: Int
    public let totalLinesEffectivelyChanged: Int
    public let moves: [MoveDetail]

    public init(
        movesDetected: Int,
        totalLinesMoved: Int,
        totalLinesEffectivelyChanged: Int,
        moves: [MoveDetail]
    ) {
        self.movesDetected = movesDetected
        self.totalLinesMoved = totalLinesMoved
        self.totalLinesEffectivelyChanged = totalLinesEffectivelyChanged
        self.moves = moves
    }

    enum CodingKeys: String, CodingKey {
        case movesDetected = "moves_detected"
        case totalLinesMoved = "total_lines_moved"
        case totalLinesEffectivelyChanged = "total_lines_effectively_changed"
        case moves
    }
}
