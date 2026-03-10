import Foundation
import RegexBuilder

public struct CommentMetadata: Codable, Sendable, Equatable {

    public struct RuleInfo: Codable, Sendable, Equatable {
        public let id: String
        public let hash: String

        public init(id: String, hash: String) {
            self.id = id
            self.hash = hash
        }
    }

    public struct FileInfo: Codable, Sendable, Equatable {
        public let path: String
        public let line: Int?
        public let blobSHA: String?

        public init(path: String, line: Int?, blobSHA: String?) {
            self.path = path
            self.line = line
            self.blobSHA = blobSHA
        }
    }

    public let version: Int
    public let rule: RuleInfo
    public let fileInfo: FileInfo?
    public let prHeadSHA: String

    public init(
        version: Int = 1,
        rule: RuleInfo,
        fileInfo: FileInfo?,
        prHeadSHA: String
    ) {
        self.version = version
        self.rule = rule
        self.fileInfo = fileInfo
        self.prHeadSHA = prHeadSHA
    }

    public func toHTMLComment() -> String {
        var lines: [String] = ["<!-- prradar:v\(version)"]
        lines.append("rule_id: \(rule.id)")
        lines.append("rule_hash: \(rule.hash)")
        if let fileInfo {
            lines.append("file: \(fileInfo.path)")
            if let line = fileInfo.line {
                lines.append("line: \(line)")
            }
            if let blobSHA = fileInfo.blobSHA {
                lines.append("file_blob_sha: \(blobSHA)")
            }
        }
        lines.append("pr_head_sha: \(prHeadSHA)")
        lines.append("-->")
        return lines.joined(separator: "\n")
    }

    nonisolated(unsafe) private static let versionRef = Reference<Substring>()
    nonisolated(unsafe) private static let fieldsRef = Reference<Substring>()

    nonisolated(unsafe) private static let metadataPattern = Regex {
        "<!--"
        OneOrMore(.whitespace)
        "prradar:v"
        Capture(as: versionRef) { OneOrMore(.digit) }
        "\n"
        Capture(as: fieldsRef) {
            ZeroOrMore(.reluctant) { CharacterClass.any }
        }
        "-->"
    }

    public static func parse(from body: String) -> CommentMetadata? {
        guard let match = body.firstMatch(of: metadataPattern) else {
            return nil
        }

        guard let version = Int(match[versionRef]) else { return nil }

        let fieldsBlock = String(match[fieldsRef])
        var fields: [String: String] = [:]
        for fieldLine in fieldsBlock.split(separator: "\n") {
            let trimmed = fieldLine.trimmingCharacters(in: .whitespaces)
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[trimmed.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        guard let ruleId = fields["rule_id"],
              let ruleHash = fields["rule_hash"],
              let prHeadSHA = fields["pr_head_sha"] else {
            return nil
        }

        let rule = RuleInfo(id: ruleId, hash: ruleHash)

        let fileInfo: FileInfo? = fields["file"].map { path in
            FileInfo(
                path: path,
                line: fields["line"].flatMap { Int($0) },
                blobSHA: fields["file_blob_sha"]
            )
        }

        return CommentMetadata(
            version: version,
            rule: rule,
            fileInfo: fileInfo,
            prHeadSHA: prHeadSHA
        )
    }

    public static func stripMetadata(from body: String) -> String {
        body.replacing(metadataPattern, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
