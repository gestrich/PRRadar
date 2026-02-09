import Foundation

/// Represents a contiguous section of lines with the same blame information
public struct BlameSection: Codable, Sendable {
    public let startLine: Int
    public let endLine: Int
    public var ownership: Ownership

    public init(startLine: Int, endLine: Int, ownership: Ownership) {
        self.startLine = startLine
        self.endLine = endLine
        self.ownership = ownership
    }

    /// Number of lines in this section
    public var lineCount: Int {
        endLine - startLine + 1
    }
}

/// Contains file content and blame information for all lines
public struct FileBlameData: Codable, Sendable, Identifiable {
    public var id: String { filePath }
    public let filePath: String
    public let lines: [String]
    public let sections: [BlameSection]

    public var fileContent: String {
        lines.joined(separator: "\n")
    }

    public init(filePath: String, fileContent: String, sections: [BlameSection]) {
        self.filePath = filePath
        self.lines = fileContent.components(separatedBy: .newlines)
        self.sections = sections
    }

    /// Get the blame section for a specific line number (1-based)
    public func section(for lineNumber: Int) -> BlameSection? {
        sections.first { section in
            lineNumber >= section.startLine && lineNumber <= section.endLine
        }
    }

    /// Get ownership for a specific line number (1-based)
    public func ownership(for lineNumber: Int) -> Ownership? {
        section(for: lineNumber)?.ownership
    }
}
