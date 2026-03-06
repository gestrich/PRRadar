import Foundation

/// Represents a complete git diff with all its hunks
@preconcurrency public struct GitDiff: Equatable, Codable, Sendable {
    /// The raw diff content
    public let rawContent: String
    /// List of parsed hunks
    public let hunks: [Hunk]
    /// The git commit hash for this diff
    public let commitHash: String

    public init(rawContent: String, hunks: [Hunk], commitHash: String) {
        self.rawContent = rawContent
        self.hunks = hunks
        self.commitHash = commitHash
    }

    /// Parse diff content into a GitDiff structure
    public static func fromDiffContent(_ diffContent: String, commitHash: String) -> GitDiff {
        let lines = diffContent.components(separatedBy: .newlines)
        var currentHunk: [String] = []
        var fileHeader: [String] = []
        var currentFile: String?
        var currentRenameFrom: String?
        var inHunk = false
        var hunks: [Hunk] = []

        func flushCurrentFile() {
            if !currentHunk.isEmpty, let file = currentFile {
                if let hunk = Hunk.fromHunkData(fileHeader: fileHeader, hunkLines: currentHunk, filePath: file, renameFrom: currentRenameFrom) {
                    hunks.append(hunk)
                }
            } else if currentRenameFrom != nil, let file = currentFile {
                // Pure rename with no @@ hunks — create a hunk from headers only
                let content = fileHeader.joined(separator: "\n")
                hunks.append(Hunk(
                    filePath: file,
                    content: content,
                    rawHeader: fileHeader,
                    renameFrom: currentRenameFrom
                ))
            }
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("diff --git") {
                flushCurrentFile()
                currentHunk = []
                fileHeader = []
                currentRenameFrom = nil

                currentFile = extractFilePath(from: line)
                fileHeader = [line]
                inHunk = false
            } else if line.hasPrefix("index ") || line.hasPrefix("--- ") || line.hasPrefix("+++ ")
                        || line.hasPrefix("new file") || line.hasPrefix("deleted file")
                        || line.hasPrefix("similarity") {
                fileHeader.append(line)
            } else if line.hasPrefix("rename from ") {
                fileHeader.append(line)
                currentRenameFrom = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                fileHeader.append(line)
            } else if line.hasPrefix("@@") {
                if !currentHunk.isEmpty, let file = currentFile {
                    if let hunk = Hunk.fromHunkData(fileHeader: fileHeader, hunkLines: currentHunk, filePath: file, renameFrom: currentRenameFrom) {
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

        flushCurrentFile()

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

    public var renamedFiles: [(from: String, to: String)] {
        hunks.compactMap { hunk in
            hunk.renameFrom.map { (from: $0, to: hunk.filePath) }
        }
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

    /// Sorted list of unique file paths in this diff.
    public var uniqueFiles: [String] {
        Array(Set(hunks.map(\.filePath))).sorted()
    }

    public var deletedFiles: Set<String> {
        Set(hunks.filter(\.isDeletedFile).map(\.filePath))
    }

    public var newFiles: Set<String> {
        Set(hunks.filter(\.isNewFile).map(\.filePath))
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
