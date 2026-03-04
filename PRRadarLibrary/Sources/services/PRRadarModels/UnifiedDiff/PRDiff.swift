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

    public static func build(
        from gitDiff: GitDiff,
        classifiedHunks: [ClassifiedHunk],
        moveReport: MoveReport?
    ) -> PRDiff {
        let moveDetails = moveReport?.moves ?? []
        let prHunks = classifiedHunks.map { hunk in
            PRHunk(
                filePath: hunk.filePath,
                oldStart: hunk.oldStart,
                newStart: hunk.newStart,
                lines: hunk.lines.map { line in
                    let moveInfo = findMoveInfo(
                        for: line,
                        in: moveDetails
                    )
                    return PRLine(from: line, moveInfo: moveInfo)
                }
            )
        }

        let stats = DiffStats.compute(from: prHunks)

        return PRDiff(
            commitHash: gitDiff.commitHash,
            rawText: gitDiff.rawContent,
            hunks: prHunks,
            moves: moveDetails,
            stats: stats
        )
    }

    private static func findMoveInfo(
        for line: ClassifiedDiffLine,
        in moves: [MoveDetail]
    ) -> MoveInfo? {
        guard line.inMovedBlock else { return nil }

        for move in moves {
            if line.lineType == .removed,
               let oldNum = line.oldLineNumber,
               line.filePath == move.sourceFile,
               move.sourceLines.count >= 2,
               oldNum >= move.sourceLines[0],
               oldNum <= move.sourceLines[1] {
                return MoveInfo(
                    sourceFile: move.sourceFile,
                    targetFile: move.targetFile,
                    isSource: true
                )
            }

            if line.lineType == .added,
               let newNum = line.newLineNumber,
               line.filePath == move.targetFile,
               move.targetLines.count >= 2,
               newNum >= move.targetLines[0],
               newNum <= move.targetLines[1] {
                return MoveInfo(
                    sourceFile: move.sourceFile,
                    targetFile: move.targetFile,
                    isSource: false
                )
            }
        }

        return nil
    }
}
