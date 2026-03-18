public struct PRDiff: Codable, Sendable, Equatable {
    public let commitHash: String
    public let rawText: String
    public let hunks: [PRHunk]
    public let moves: [MoveDetail]
    public let stats: DiffStats

    public init(
        commitHash: String,
        rawText: String,
        hunks: [PRHunk],
        moves: [MoveDetail],
        stats: DiffStats
    ) {
        self.commitHash = commitHash
        self.rawText = rawText
        self.hunks = hunks
        self.moves = moves
        self.stats = stats
    }

    public var changedFiles: [String] {
        Array(Set(hunks.map(\.filePath)).sorted())
    }

    public func hunks(forFile filePath: String) -> [PRHunk] {
        hunks.filter { $0.filePath == filePath }
    }

    /// Build a PRDiff from a raw GitDiff with no move analysis (fallback path).
    public static func fromRawDiff(_ gitDiff: GitDiff) -> PRDiff {
        let prHunks = gitDiff.hunks.map { PRHunk.fromHunk($0) }
        return PRDiff(
            commitHash: gitDiff.commitHash,
            rawText: gitDiff.rawContent,
            hunks: prHunks,
            moves: [],
            stats: DiffStats.compute(from: prHunks)
        )
    }

    /// Reconstruct the full GitDiff by re-parsing from rawText.
    public func toGitDiff() -> GitDiff {
        GitDiff.fromDiffContent(rawText, commitHash: commitHash)
    }

    /// Derive the effective GitDiff by filtering out fully-moved hunks.
    public func toEffectiveGitDiff() -> GitDiff {
        let fullDiff = toGitDiff()
        let effectiveHunks = fullDiff.hunks.filter { gitHunk in
            let matchingPRHunk = hunks.first {
                $0.filePath == gitHunk.filePath
                    && $0.oldStart == gitHunk.oldStart
                    && $0.newStart == gitHunk.newStart
            }
            return matchingPRHunk.map { !$0.isMoved } ?? true
        }
        return GitDiff(rawContent: "", hunks: effectiveHunks, commitHash: commitHash)
    }

    /// Return a new PRDiff with hunks for excluded file paths removed.
    ///
    /// Uses the same glob/fnmatch matching as rule `applies_to.exclude_patterns`.
    /// Patterns without `/` match against filename only; patterns with `/` match the full path.
    public func excludingPaths(_ patterns: [String]) -> PRDiff {
        guard !patterns.isEmpty else { return self }
        let filtered = hunks.filter { hunk in
            !patterns.contains { pattern in
                AppliesTo.fnmatch(hunk.filePath, pattern: pattern)
            }
        }
        return PRDiff(
            commitHash: commitHash,
            rawText: rawText,
            hunks: filtered,
            moves: moves,
            stats: DiffStats.compute(from: filtered)
        )
    }

    /// Derive a MoveReport from the moves and stats already on this diff.
    public var derivedMoveReport: MoveReport {
        MoveReport(
            movesDetected: moves.count,
            totalLinesMoved: moves.reduce(0) { $0 + $1.matchedLines },
            totalLinesEffectivelyChanged: stats.linesChanged + stats.linesAdded + stats.linesRemoved,
            moves: moves
        )
    }
}
