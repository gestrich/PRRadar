public struct PRLine: Codable, Sendable, Equatable {
    public let content: String
    public let rawLine: String
    public let diffType: DiffLineType
    public let contentChange: ContentChange
    public let pairing: Pairing?
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let filePath: String
    public let inlineChanges: [InlineChangeSpan]?
    /// `true` when this is a paired `.modified` line whose only difference from its counterpart
    /// is leading/trailing whitespace. Interior whitespace changes (e.g. `* name` → `*name`) are
    /// NOT flagged. Always `false` for `.added`, `.deleted`, and `.unchanged` lines.
    public let isSurroundingWhitespaceOnlyChange: Bool

    public var stableID: String {
        "\(filePath):\(diffType):\(oldLineNumber ?? -1):\(newLineNumber ?? -1)"
    }

    /// Returns `(sourceFile, targetFile)` when this line is part of a cross-file move, nil otherwise.
    public var crossFileMoveFiles: (source: String, target: String)? {
        guard let pairing, pairing.counterpart.filePath != filePath else { return nil }
        switch pairing.role {
        case .before: return (source: filePath, target: pairing.counterpart.filePath)
        case .after:  return (source: pairing.counterpart.filePath, target: filePath)
        }
    }

    public init(
        content: String,
        rawLine: String,
        diffType: DiffLineType,
        contentChange: ContentChange,
        pairing: Pairing? = nil,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        filePath: String,
        inlineChanges: [InlineChangeSpan]? = nil,
        isSurroundingWhitespaceOnlyChange: Bool = false
    ) {
        self.content = content
        self.rawLine = rawLine
        self.diffType = diffType
        self.contentChange = contentChange
        self.pairing = pairing
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.filePath = filePath
        self.inlineChanges = inlineChanges
        self.isSurroundingWhitespaceOnlyChange = isSurroundingWhitespaceOnlyChange
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
