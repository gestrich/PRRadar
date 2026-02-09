import Foundation
import CryptoKit

// MARK: - Phase 2: Focus Area Models

public enum FocusType: String, Codable, Sendable {
    case file
    case method
}

/// A focus area identified by the pipeline — a reviewable unit of code within a hunk.
public struct FocusArea: Codable, Sendable, Equatable {
    public let focusId: String
    public let filePath: String
    public let startLine: Int
    public let endLine: Int
    public let description: String
    public let hunkIndex: Int
    public let hunkContent: String
    public let focusType: FocusType

    public init(
        focusId: String,
        filePath: String,
        startLine: Int,
        endLine: Int,
        description: String,
        hunkIndex: Int,
        hunkContent: String,
        focusType: FocusType = .file
    ) {
        self.focusId = focusId
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.description = description
        self.hunkIndex = hunkIndex
        self.hunkContent = hunkContent
        self.focusType = focusType
    }

    enum CodingKeys: String, CodingKey {
        case focusId = "focus_id"
        case filePath = "file_path"
        case startLine = "start_line"
        case endLine = "end_line"
        case description
        case hunkIndex = "hunk_index"
        case hunkContent = "hunk_content"
        case focusType = "focus_type"
    }

    // MARK: - Content Extraction

    /// Extract only the lines within focus bounds from hunk content.
    ///
    /// Returns annotated diff lines (with +/- markers and line numbers)
    /// for just the focused region within `[startLine, endLine]`.
    public func getFocusedContent() -> String {
        let lines = hunkContent.components(separatedBy: "\n")

        // Find where diff body starts (after @@ line)
        var bodyStart = 0
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("@@") {
                bodyStart = i
                break
            }
        }

        // Extract lines within [startLine, endLine] range
        var focusedLines = [lines[bodyStart]] // Include @@ header
        for line in lines[(bodyStart + 1)...] {
            guard line.contains(": ") else { continue }
            let lineNumStr = line.components(separatedBy: ": ").first?.trimmingCharacters(in: .whitespaces) ?? ""
            if let lineNum = Int(lineNumStr), startLine <= lineNum && lineNum <= endLine {
                focusedLines.append(line)
            }
        }

        return focusedLines.joined(separator: "\n")
    }

    /// Extract diff context centered on a specific line number.
    ///
    /// - Parameters:
    ///   - lineNumber: Target line number in the new file. If nil, returns the first few lines.
    ///   - contextLines: Number of lines to show before and after target.
    /// - Returns: Formatted diff excerpt with line numbers and +/- markers.
    public func getContextAroundLine(_ lineNumber: Int?, contextLines: Int = 3) -> String {
        let lines = hunkContent.components(separatedBy: "\n")

        var bodyStart = 0
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("@@") {
                bodyStart = i
                break
            }
        }

        let bodyLines = Array(lines[bodyStart...])

        guard let lineNumber else {
            return bodyLines.prefix(1 + contextLines * 2).joined(separator: "\n")
        }

        // Find the line matching our target line number
        var targetIdx: Int?
        for (i, line) in bodyLines.enumerated() {
            if line.hasPrefix("@@") { continue }
            if line.contains(": ") {
                let prefix = line.components(separatedBy: ": ").first?.trimmingCharacters(in: .whitespaces) ?? ""
                if let num = Int(prefix), num == lineNumber {
                    targetIdx = i
                    break
                }
            }
        }

        guard let targetIdx else {
            return bodyLines.prefix(1 + contextLines * 2).joined(separator: "\n")
        }

        let start = max(0, targetIdx - contextLines)
        let end = min(bodyLines.count, targetIdx + contextLines + 1)

        return Array(bodyLines[start..<end]).joined(separator: "\n")
    }

    /// SHA-256 short hash of the hunk content for grouping.
    public func contentHash() -> String {
        let data = Data(hunkContent.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
