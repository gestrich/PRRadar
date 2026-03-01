import Foundation

// MARK: - DiffLine

public enum DiffLineType: String, Codable, Sendable {
    case added
    case removed
    case context
    case header
}

/// A single line from a diff with metadata including line numbers.
public struct DiffLine: Sendable {
    public let content: String
    public let rawLine: String
    public let lineType: DiffLineType
    public let newLineNumber: Int?
    public let oldLineNumber: Int?

    public init(
        content: String,
        rawLine: String,
        lineType: DiffLineType,
        newLineNumber: Int? = nil,
        oldLineNumber: Int? = nil
    ) {
        self.content = content
        self.rawLine = rawLine
        self.lineType = lineType
        self.newLineNumber = newLineNumber
        self.oldLineNumber = oldLineNumber
    }

    public var isChanged: Bool {
        lineType == .added || lineType == .removed
    }
}

// MARK: - Hunk

/// Represents a single hunk from a git diff
@preconcurrency public struct Hunk: Identifiable, Equatable, Codable, Sendable {
    /// The path of the modified file (from b/ path in diff)
    public let filePath: String
    /// The full content of the hunk including header
    public let content: String
    /// The raw header lines from the diff
    public let rawHeader: [String]
    /// Starting line number in the old file
    public let oldStart: Int
    /// Number of lines in the old file section
    public let oldLength: Int
    /// Starting line number in the new file
    public let newStart: Int
    /// Number of lines in the new file section
    public let newLength: Int
    /// The original path before rename, if this file was renamed (from `rename from` header)
    public let renameFrom: String?

    public init(
        filePath: String,
        content: String,
        rawHeader: [String] = [],
        oldStart: Int = 0,
        oldLength: Int = 0,
        newStart: Int = 0,
        newLength: Int = 0,
        renameFrom: String? = nil
    ) {
        self.filePath = filePath
        self.content = content
        self.rawHeader = rawHeader
        self.oldStart = oldStart
        self.oldLength = oldLength
        self.newStart = newStart
        self.newLength = newLength
        self.renameFrom = renameFrom
    }

    public var id: String {
        chunkName
    }

    public var chunkName: String {
        let safeName = filePath.replacingOccurrences(of: "/", with: "_")
        return "\(safeName)_L\(newStart)"
    }

    public var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    public var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension
    }

    /// Get just the diff lines (without headers or @@ lines)
    public var diffLines: [String] {
        let lines = content.components(separatedBy: .newlines)
        var result: [String] = []
        var inDiffContent = false

        for line in lines {
            if !inDiffContent {
                if line.hasPrefix("diff --git") ||
                   line.hasPrefix("index ") ||
                   line.hasPrefix("--- ") ||
                   line.hasPrefix("+++ ") {
                    continue
                } else if line.hasPrefix("@@") {
                    inDiffContent = true
                    continue
                }
            }

            if inDiffContent && !line.isEmpty {
                result.append(line)
            }
        }

        return result
    }

    /// Create a Hunk from raw diff data
    public static func fromHunkData(fileHeader: [String], hunkLines: [String], filePath: String?, renameFrom: String? = nil) -> Hunk? {
        guard let filePath, !filePath.isEmpty else { return nil }

        var oldStart = 0
        var oldLength = 0
        var newStart = 0
        var newLength = 0

        for line in hunkLines {
            if line.hasPrefix("@@") {
                let pattern = #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
                let regex = try? NSRegularExpression(pattern: pattern, options: [])
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)

                if let match = regex?.firstMatch(in: line, options: [], range: nsRange) {
                    if let oldStartRange = Range(match.range(at: 1), in: line) {
                        oldStart = Int(line[oldStartRange]) ?? 0
                    }
                    if let oldLengthRange = Range(match.range(at: 2), in: line) {
                        oldLength = Int(line[oldLengthRange]) ?? 1
                    } else {
                        oldLength = 1
                    }
                    if let newStartRange = Range(match.range(at: 3), in: line) {
                        newStart = Int(line[newStartRange]) ?? 0
                    }
                    if let newLengthRange = Range(match.range(at: 4), in: line) {
                        newLength = Int(line[newLengthRange]) ?? 1
                    } else {
                        newLength = 1
                    }
                }
                break
            }
        }

        let content = (fileHeader + hunkLines).joined(separator: "\n")

        return Hunk(
            filePath: filePath,
            content: content,
            rawHeader: fileHeader,
            oldStart: oldStart,
            oldLength: oldLength,
            newStart: newStart,
            newLength: newLength,
            renameFrom: renameFrom
        )
    }

    // MARK: - Line Number Annotation

    /// Return hunk content with target file line numbers prepended.
    ///
    /// Format:
    /// - Added (+) and context lines get: `"  5: +code here"`
    /// - Deleted (-) lines get: `"   -: -deleted code"` (no line number)
    /// - Header lines are preserved as-is
    public func getAnnotatedContent() -> String {
        let lines = content.components(separatedBy: "\n")
        var annotated: [String] = []
        var newLine = newStart
        var inHunkBody = false

        for line in lines {
            if line.hasPrefix("@@") {
                annotated.append(line)
                inHunkBody = true
            } else if !inHunkBody {
                annotated.append(line)
            } else if line.hasPrefix("-") {
                annotated.append("   -: \(line)")
            } else if line.hasPrefix("+") {
                annotated.append(String(format: "%4d: %@", newLine, line))
                newLine += 1
            } else if line.hasPrefix(" ") || line.isEmpty {
                if !line.isEmpty {
                    annotated.append(String(format: "%4d: %@", newLine, line))
                    newLine += 1
                } else {
                    annotated.append(line)
                }
            } else {
                annotated.append(line)
            }
        }

        return annotated.joined(separator: "\n")
    }

    // MARK: - Structured DiffLine Parsing

    /// Parse hunk content into structured `DiffLine` objects with line numbers and types.
    public func getDiffLines() -> [DiffLine] {
        let lines = content.components(separatedBy: "\n")
        var result: [DiffLine] = []
        var newLine = newStart
        var oldLine = oldStart
        var inHunkBody = false

        for line in lines {
            if line.hasPrefix("@@") {
                inHunkBody = true
                result.append(DiffLine(content: line, rawLine: line, lineType: .header))
            } else if !inHunkBody {
                result.append(DiffLine(content: line, rawLine: line, lineType: .header))
            } else if line.hasPrefix("-") {
                result.append(DiffLine(
                    content: String(line.dropFirst()),
                    rawLine: line,
                    lineType: .removed,
                    oldLineNumber: oldLine
                ))
                oldLine += 1
            } else if line.hasPrefix("+") {
                result.append(DiffLine(
                    content: String(line.dropFirst()),
                    rawLine: line,
                    lineType: .added,
                    newLineNumber: newLine
                ))
                newLine += 1
            } else if line.hasPrefix(" ") || (line.isEmpty && inHunkBody) {
                let content = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                if !line.isEmpty {
                    result.append(DiffLine(
                        content: content,
                        rawLine: line,
                        lineType: .context,
                        newLineNumber: newLine,
                        oldLineNumber: oldLine
                    ))
                    newLine += 1
                    oldLine += 1
                }
            }
        }

        return result
    }

    /// Get only added lines (lines starting with +).
    public func getAddedLines() -> [DiffLine] {
        getDiffLines().filter { $0.lineType == .added }
    }

    /// Get only removed lines (lines starting with -).
    public func getRemovedLines() -> [DiffLine] {
        getDiffLines().filter { $0.lineType == .removed }
    }

    /// Get all changed lines (both added and removed).
    public func getChangedLines() -> [DiffLine] {
        getDiffLines().filter { $0.isChanged }
    }

    /// Get the text content of changed lines only (for grep pattern matching).
    public func getChangedContent() -> String {
        getChangedLines().map(\.content).joined(separator: "\n")
    }

    /// Extract changed content from diff text (handles both raw and annotated formats).
    public static func extractChangedContent(from diffText: String) -> String {
        var changedLines: [String] = []
        var inHunkBody = false

        for line in diffText.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                inHunkBody = true
            } else if inHunkBody {
                // Raw format
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    changedLines.append(String(line.dropFirst()))
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    changedLines.append(String(line.dropFirst()))
                }
                // Annotated format: "123: +code" or "   -: -code"
                else if line.contains(": +") {
                    if let idx = line.range(of: ": +") {
                        changedLines.append(String(line[idx.upperBound...]))
                    }
                } else if line.contains(": -") && line.trimmingCharacters(in: .whitespaces).hasPrefix("-:") {
                    if let idx = line.range(of: ": -") {
                        changedLines.append(String(line[idx.upperBound...]))
                    }
                }
            }
        }

        return changedLines.joined(separator: "\n")
    }
}
