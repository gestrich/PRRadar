import Foundation

/// Represents a complete git diff with all its hunks
@preconcurrency public struct GitDiff: Equatable, Codable, Sendable {
    /// The raw diff content
    public let rawContent: String
    /// List of parsed hunks
    public let hunks: [Hunk]
    /// The git commit hash for this diff (optional)
    public let commitHash: String?

    public init(rawContent: String, hunks: [Hunk], commitHash: String? = nil) {
        self.rawContent = rawContent
        self.hunks = hunks
        self.commitHash = commitHash
    }

    /// Parse diff content into a GitDiff structure
    public static func fromDiffContent(_ diffContent: String, commitHash: String? = nil) -> GitDiff {
        let lines = diffContent.components(separatedBy: .newlines)
        var currentHunk: [String] = []
        var fileHeader: [String] = []
        var currentFile: String?
        var inHunk = false
        var hunks: [Hunk] = []

        var i = 0
        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("diff --git") {
                if !currentHunk.isEmpty, let file = currentFile {
                    if let hunk = Hunk.fromHunkData(fileHeader: fileHeader, hunkLines: currentHunk, filePath: file) {
                        hunks.append(hunk)
                    }
                    currentHunk = []
                    fileHeader = []
                }

                currentFile = extractFilePath(from: line)
                fileHeader = [line]
                inHunk = false
            } else if line.hasPrefix("index ") {
                fileHeader.append(line)
            } else if line.hasPrefix("--- ") {
                fileHeader.append(line)
            } else if line.hasPrefix("+++ ") {
                fileHeader.append(line)
            } else if line.hasPrefix("@@") {
                if !currentHunk.isEmpty, let file = currentFile {
                    if let hunk = Hunk.fromHunkData(fileHeader: fileHeader, hunkLines: currentHunk, filePath: file) {
                        hunks.append(hunk)
                    }
                    currentHunk = []
                }
                inHunk = true
                currentHunk.append(line)
            } else if inHunk {
                currentHunk.append(line)
            }

            i += 1
        }

        if !currentHunk.isEmpty, let file = currentFile {
            if let hunk = Hunk.fromHunkData(fileHeader: fileHeader, hunkLines: currentHunk, filePath: file) {
                hunks.append(hunk)
            }
        }

        return GitDiff(rawContent: diffContent, hunks: hunks, commitHash: commitHash)
    }

    public var isEmpty: Bool {
        rawContent.isEmpty || hunks.isEmpty
    }

    public func getHunks(byFileExtensions extensions: [String]?) -> [Hunk] {
        guard let extensions else { return hunks }
        return hunks.filter { extensions.contains($0.fileExtension) }
    }

    public func getHunks(byFilePath filePath: String) -> [Hunk] {
        hunks.filter { $0.filePath == filePath }
    }

    public func findHunk(containingLine lineNumber: Int, inFile filePath: String) -> Hunk? {
        let fileHunks = getHunks(byFilePath: filePath)

        for hunk in fileHunks {
            let hunkEndLine = hunk.newStart + hunk.newLength - 1
            if lineNumber >= hunk.newStart && lineNumber <= hunkEndLine {
                return hunk
            }
        }

        return nil
    }

    public var changedFiles: [String] {
        Array(Set(hunks.map(\.filePath))).sorted()
    }

    public func diffSections() -> [DiffSection] {
        var sections: [String: [DiffLine]] = [:]

        for hunk in hunks {
            if sections[hunk.filePath] == nil {
                sections[hunk.filePath] = []
            }

            for line in hunk.diffLines {
                let type: DiffLineType
                if line.hasPrefix("+") {
                    type = .addition
                } else if line.hasPrefix("-") {
                    type = .deletion
                } else {
                    type = .context
                }
                sections[hunk.filePath]?.append(DiffLine(content: line, type: type))
            }
        }

        return sections.map { DiffSection(filePath: $0.key, lines: $0.value) }
            .sorted { $0.filePath < $1.filePath }
    }

    public func getChangedLines() -> [String: Set<Int>] {
        var changedLines: [String: Set<Int>] = [:]

        for hunk in hunks {
            if changedLines[hunk.filePath] == nil {
                changedLines[hunk.filePath] = Set<Int>()
            }

            let lines = hunk.content.components(separatedBy: .newlines)
            var currentNewLine = hunk.newStart
            var inDiffContent = false

            for line in lines {
                if line.hasPrefix("@@") {
                    inDiffContent = true
                    continue
                } else if !inDiffContent {
                    continue
                } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    changedLines[hunk.filePath]?.insert(currentNewLine)
                    currentNewLine += 1
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    continue
                } else if line.hasPrefix(" ") {
                    currentNewLine += 1
                } else if inDiffContent && !line.isEmpty {
                    currentNewLine += 1
                }
            }
        }

        return changedLines
    }

    private static func extractFilePath(from line: String) -> String? {
        let quotedPattern = #"diff --git "?a/([^"]*)"? "?b/([^"]*)"?"#
        if let regex = try? NSRegularExpression(pattern: quotedPattern, options: []) {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: nsRange),
               let range = Range(match.range(at: 2), in: line) {
                return String(line[range]).trimmingCharacters(in: .whitespaces)
            }
        }

        let simplePattern = #"diff --git a/(.*?) b/(.*?)(?:\s|$)"#
        if let regex = try? NSRegularExpression(pattern: simplePattern, options: []) {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: nsRange),
               let range = Range(match.range(at: 2), in: line) {
                return String(line[range]).trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }
}

/// Represents a section of diff lines for a single file
public struct DiffSection: Identifiable, Equatable {
    public let id = UUID()
    public let filePath: String
    public let lines: [DiffLine]
    public let isStaged: Bool

    public init(filePath: String, lines: [DiffLine], isStaged: Bool = false) {
        self.filePath = filePath
        self.lines = lines
        self.isStaged = isStaged
    }
}

/// Represents a single line in a diff for display purposes
public struct DiffLine: Identifiable, Equatable {
    public let id = UUID()
    public let content: String
    public let type: DiffLineType

    public init(content: String, type: DiffLineType) {
        self.content = content
        self.type = type
    }
}

public enum DiffLineType: Equatable {
    case addition
    case deletion
    case context
}
