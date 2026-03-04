public struct PRLine: Codable, Sendable, Equatable {
    public let content: String
    public let rawLine: String
    public let diffType: DiffLineType
    public let changeKind: ChangeKind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let filePath: String
    public let move: MoveInfo?
    public let inlineChanges: [InlineChangeSpan]?

    public init(
        content: String,
        rawLine: String,
        diffType: DiffLineType,
        changeKind: ChangeKind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        filePath: String,
        move: MoveInfo?,
        inlineChanges: [InlineChangeSpan]? = nil
    ) {
        self.content = content
        self.rawLine = rawLine
        self.diffType = diffType
        self.changeKind = changeKind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.filePath = filePath
        self.move = move
        self.inlineChanges = inlineChanges
    }

    public init(from classifiedLine: ClassifiedDiffLine, moveInfo: MoveInfo?) {
        self.content = classifiedLine.content
        self.rawLine = classifiedLine.rawLine
        self.diffType = classifiedLine.lineType
        self.changeKind = classifiedLine.changeKind
        self.oldLineNumber = classifiedLine.oldLineNumber
        self.newLineNumber = classifiedLine.newLineNumber
        self.filePath = classifiedLine.filePath
        self.move = moveInfo
        self.inlineChanges = nil
    }
}

// MARK: - MoveInfo

public struct MoveInfo: Codable, Sendable, Equatable {
    public let sourceFile: String
    public let targetFile: String
    public let isSource: Bool

    public init(sourceFile: String, targetFile: String, isSource: Bool) {
        self.sourceFile = sourceFile
        self.targetFile = targetFile
        self.isSource = isSource
    }
}

// MARK: - InlineChangeSpan

public struct InlineChangeSpan: Codable, Sendable, Equatable {
    public let range: Range<Int>
    public let kind: Kind

    public enum Kind: String, Codable, Sendable, Equatable {
        case added
        case removed
    }

    public init(range: Range<Int>, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}
