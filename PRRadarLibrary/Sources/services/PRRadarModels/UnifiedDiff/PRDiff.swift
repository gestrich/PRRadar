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
}
