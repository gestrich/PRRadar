public struct PRHunk: Codable, Sendable, Equatable {
    public let filePath: String
    public let oldStart: Int
    public let newStart: Int
    public let lines: [PRLine]

    public init(filePath: String, oldStart: Int, newStart: Int, lines: [PRLine]) {
        self.filePath = filePath
        self.oldStart = oldStart
        self.newStart = newStart
        self.lines = lines
    }

    public var isMoved: Bool {
        let nonContext = lines.filter { $0.diffType != .context }
        guard !nonContext.isEmpty else { return false }
        return nonContext.allSatisfy { $0.move != nil && $0.changeKind == .unchanged }
    }

    public var hasNewCode: Bool {
        lines.contains { $0.changeKind == .added }
    }

    public var hasChangesInMove: Bool {
        lines.contains { $0.changeKind == .changed && $0.move != nil }
    }

    public var newCodeLines: [PRLine] {
        lines.filter { $0.changeKind == .added }
    }

    public var changedLines: [PRLine] {
        lines.filter { $0.changeKind != .unchanged }
    }

    public func relevantLines(newCodeLinesOnly: Bool) -> [PRLine] {
        newCodeLinesOnly ? newCodeLines : changedLines
    }

    public func relevantLineNumbers(newCodeLinesOnly: Bool) -> Set<Int> {
        Set(relevantLines(newCodeLinesOnly: newCodeLinesOnly)
            .compactMap { $0.newLineNumber ?? $0.oldLineNumber })
    }

    public static func filterForFocusArea(
        _ hunks: [PRHunk],
        focusArea: FocusArea
    ) -> [PRHunk] {
        hunks.compactMap { hunk in
            guard hunk.filePath == focusArea.filePath else { return nil }
            let filteredLines = hunk.lines.filter { line in
                guard let lineNum = line.newLineNumber ?? line.oldLineNumber else { return false }
                return lineNum >= focusArea.startLine && lineNum <= focusArea.endLine
            }
            guard !filteredLines.isEmpty else { return nil }
            return PRHunk(
                filePath: hunk.filePath,
                oldStart: hunk.oldStart,
                newStart: hunk.newStart,
                lines: filteredLines
            )
        }
    }
}
