public enum LineClassification: String, Codable, Sendable {
    case new
    case moved
    case changedInMove
    case removed
    case movedRemoval
    case context
}

public struct ClassifiedDiffLine: Sendable {
    public let content: String
    public let rawLine: String
    public let lineType: DiffLineType
    public let classification: LineClassification
    public let newLineNumber: Int?
    public let oldLineNumber: Int?
    public let filePath: String
    public let moveCandidate: MoveCandidate?

    public init(
        content: String,
        rawLine: String,
        lineType: DiffLineType,
        classification: LineClassification,
        newLineNumber: Int?,
        oldLineNumber: Int?,
        filePath: String,
        moveCandidate: MoveCandidate?
    ) {
        self.content = content
        self.rawLine = rawLine
        self.lineType = lineType
        self.classification = classification
        self.newLineNumber = newLineNumber
        self.oldLineNumber = oldLineNumber
        self.filePath = filePath
        self.moveCandidate = moveCandidate
    }
}
