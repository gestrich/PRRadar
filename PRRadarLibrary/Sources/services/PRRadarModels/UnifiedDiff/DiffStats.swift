public struct DiffStats: Codable, Sendable, Equatable {
    public let linesAdded: Int
    public let linesRemoved: Int
    public let linesMoved: Int
    public let linesChanged: Int

    public init(linesAdded: Int, linesRemoved: Int, linesMoved: Int, linesChanged: Int) {
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.linesMoved = linesMoved
        self.linesChanged = linesChanged
    }

    public static func compute(from hunks: [PRHunk]) -> DiffStats {
        var added = 0
        var removed = 0
        var moved = 0
        var changed = 0

        for hunk in hunks {
            for line in hunk.lines {
                guard line.diffType != .context && line.diffType != .header else { continue }
                switch line.changeKind {
                case .added:
                    added += 1
                case .removed:
                    removed += 1
                case .changed:
                    changed += 1
                case .unchanged:
                    if line.move != nil {
                        moved += 1
                    }
                }
            }
        }

        return DiffStats(
            linesAdded: added,
            linesRemoved: removed,
            linesMoved: moved,
            linesChanged: changed
        )
    }
}
