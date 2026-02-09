import Foundation

// MARK: - Phase 3: Rule Models

/// File pattern matching configuration for a rule.
public struct AppliesTo: Codable, Sendable, Equatable {
    public let filePatterns: [String]?
    public let excludePatterns: [String]?

    public init(filePatterns: [String]? = nil, excludePatterns: [String]? = nil) {
        self.filePatterns = filePatterns
        self.excludePatterns = excludePatterns
    }

    enum CodingKeys: String, CodingKey {
        case filePatterns = "file_patterns"
        case excludePatterns = "exclude_patterns"
    }

    /// Check if a file path matches the applies_to criteria.
    ///
    /// - Excluded files always return false
    /// - If no include patterns, matches everything not excluded
    /// - Otherwise, at least one include pattern must match
    public func matchesFile(_ filePath: String) -> Bool {
        if let excludePatterns, !excludePatterns.isEmpty {
            for pattern in excludePatterns {
                if Self.fnmatch(filePath, pattern: pattern) {
                    return false
                }
            }
        }

        guard let filePatterns, !filePatterns.isEmpty else {
            return true
        }

        return filePatterns.contains { pattern in
            Self.fnmatch(filePath, pattern: pattern)
        }
    }

    /// Simple glob/fnmatch-style matching supporting `*` and `**` patterns.
    ///
    /// If the pattern contains no `/` characters, it matches against the filename only.
    /// Otherwise, it matches against the full path.
    static func fnmatch(_ string: String, pattern: String) -> Bool {
        // If pattern has no path separators, match against filename only
        let matchString: String
        if !pattern.contains("/") {
            matchString = (string as NSString).lastPathComponent
        } else {
            matchString = string
        }
        
        // Convert glob pattern to regex
        var regex = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex && pattern[next] == "*" {
                    // ** matches any path component
                    let afterStars = pattern.index(after: next)
                    if afterStars < pattern.endIndex && pattern[afterStars] == "/" {
                        regex += "(?:.*/)?"
                        i = pattern.index(after: afterStars)
                        continue
                    } else {
                        regex += ".*"
                        i = afterStars
                        continue
                    }
                } else {
                    // * matches anything except /
                    regex += "[^/]*"
                }
            } else if c == "?" {
                regex += "[^/]"
            } else if c == "." || c == "(" || c == ")" || c == "+" || c == "^" || c == "$" || c == "{" || c == "}" || c == "[" || c == "]" || c == "|" || c == "\\" {
                regex += "\\\(c)"
            } else {
                regex += String(c)
            }
            i = pattern.index(after: i)
        }
        regex += "$"

        return (try? NSRegularExpression(pattern: regex, options: []))
            .flatMap { $0.firstMatch(in: matchString, range: NSRange(matchString.startIndex..., in: matchString)) } != nil
    }
}

/// Grep pattern configuration for a rule.
public struct GrepPatterns: Codable, Sendable, Equatable {
    public let all: [String]?
    public let any: [String]?

    public init(all: [String]? = nil, any: [String]? = nil) {
        self.all = all
        self.any = any
    }

    /// Check if text matches the grep pattern criteria.
    ///
    /// - If `all` patterns set: ALL must match
    /// - If `any` patterns set: at least ONE must match
    /// - If both: both conditions must be satisfied
    /// - If neither: returns true (no filtering)
    public func matches(_ text: String) -> Bool {
        let hasAll = all != nil && !(all!.isEmpty)
        let hasAny = any != nil && !(any!.isEmpty)

        if !hasAll && !hasAny {
            return true
        }

        let allMatch: Bool
        if let allPatterns = all, !allPatterns.isEmpty {
            allMatch = allPatterns.allSatisfy { pattern in
                (try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]))
                    .flatMap { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) } != nil
            }
        } else {
            allMatch = true
        }

        let anyMatch: Bool
        if let anyPatterns = any, !anyPatterns.isEmpty {
            anyMatch = anyPatterns.contains { pattern in
                (try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]))
                    .flatMap { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) } != nil
            }
        } else {
            anyMatch = true
        }

        return allMatch && anyMatch
    }

    public var hasPatterns: Bool {
        (all != nil && !(all!.isEmpty)) || (any != nil && !(any!.isEmpty))
    }
}

/// A review rule loaded from a markdown file with YAML frontmatter or from JSON.
public struct ReviewRule: Codable, Sendable, Equatable {
    public let name: String
    public let filePath: String
    public let description: String
    public let category: String
    public let focusType: FocusType
    public let content: String
    public let model: String?
    public let documentationLink: String?
    public let relevantClaudeSkill: String?
    public let ruleUrl: String?
    public let appliesTo: AppliesTo?
    public let grep: GrepPatterns?

    public init(
        name: String,
        filePath: String,
        description: String,
        category: String,
        focusType: FocusType = .file,
        content: String,
        model: String? = nil,
        documentationLink: String? = nil,
        relevantClaudeSkill: String? = nil,
        ruleUrl: String? = nil,
        appliesTo: AppliesTo? = nil,
        grep: GrepPatterns? = nil
    ) {
        self.name = name
        self.filePath = filePath
        self.description = description
        self.category = category
        self.focusType = focusType
        self.content = content
        self.model = model
        self.documentationLink = documentationLink
        self.relevantClaudeSkill = relevantClaudeSkill
        self.ruleUrl = ruleUrl
        self.appliesTo = appliesTo
        self.grep = grep
    }

    enum CodingKeys: String, CodingKey {
        case name
        case filePath = "file_path"
        case description
        case category
        case focusType = "focus_type"
        case content
        case model
        case documentationLink = "documentation_link"
        case relevantClaudeSkill = "relevant_claude_skill"
        case ruleUrl = "rule_url"
        case appliesTo = "applies_to"
        case grep
    }

    // MARK: - File Parsing

    /// Load a rule from a markdown file with YAML frontmatter.
    ///
    /// The file format is:
    /// ```
    /// ---
    /// description: ...
    /// category: ...
    /// applies_to:
    ///   file_patterns: ["*.swift"]
    /// ---
    /// # Rule content here
    /// ```
    public static func fromFile(_ url: URL) throws -> ReviewRule {
        let text = try String(contentsOf: url, encoding: .utf8)
        let (frontmatter, body) = parseFrontmatter(text)

        let focusTypeStr = frontmatter["focus_type"] as? String ?? "file"
        let focusType = FocusType(rawValue: focusTypeStr) ?? .file

        let appliesTo: AppliesTo?
        if let appliesToDict = frontmatter["applies_to"] as? [String: Any] {
            let filePatterns = appliesToDict["file_patterns"] as? [String]
            let excludePatterns = appliesToDict["exclude_patterns"] as? [String]
            appliesTo = AppliesTo(filePatterns: filePatterns, excludePatterns: excludePatterns)
        } else {
            appliesTo = nil
        }

        let grep: GrepPatterns?
        if let grepDict = frontmatter["grep"] as? [String: Any] {
            let allPatterns = grepDict["all"] as? [String]
            let anyPatterns = grepDict["any"] as? [String]
            grep = GrepPatterns(all: allPatterns, any: anyPatterns)
        } else {
            grep = nil
        }

        return ReviewRule(
            name: url.deletingPathExtension().lastPathComponent,
            filePath: url.path,
            description: frontmatter["description"] as? String ?? "",
            category: frontmatter["category"] as? String ?? "",
            focusType: focusType,
            content: body.trimmingCharacters(in: .whitespacesAndNewlines),
            model: frontmatter["model"] as? String,
            documentationLink: frontmatter["documentation_link"] as? String,
            relevantClaudeSkill: frontmatter["relevantClaudeSkill"] as? String,
            appliesTo: appliesTo,
            grep: grep
        )
    }

    // MARK: - Matching

    /// Check if this rule applies to a given file path.
    public func appliesToFile(_ path: String) -> Bool {
        guard let appliesTo else { return true }
        return appliesTo.matchesFile(path)
    }

    /// Check if diff content matches the grep patterns.
    public func matchesDiffContent(_ diffText: String) -> Bool {
        guard let grep else { return true }
        return grep.matches(diffText)
    }

    /// Check if this rule should be evaluated for a file and diff.
    public func shouldEvaluate(filePath path: String, diffText: String) -> Bool {
        appliesToFile(path) && matchesDiffContent(diffText)
    }

    // MARK: - Frontmatter Parsing

    /// Parse YAML frontmatter from markdown text.
    ///
    /// Handles the `---` delimited format. Uses a simple key-value parser
    /// that supports strings, lists, and nested dictionaries (covers the
    /// subset of YAML used in rule files).
    static func parseFrontmatter(_ text: String) -> ([String: Any], String) {
        guard text.hasPrefix("---") else {
            return ([:], text)
        }

        // Split on --- delimiters
        let parts = text.components(separatedBy: "---")
        guard parts.count >= 3 else {
            return ([:], text)
        }

        // parts[0] is empty (before first ---), parts[1] is frontmatter, parts[2+] is content
        let yamlText = parts[1]
        let content = parts.dropFirst(2).joined(separator: "---")

        let frontmatter = parseSimpleYAML(yamlText)
        return (frontmatter, content)
    }

    /// Process YAML escape sequences in a string.
    private static func unescapeYAMLString(_ str: String) -> String {
        var result = ""
        var i = str.startIndex
        while i < str.endIndex {
            if str[i] == "\\" && str.index(after: i) < str.endIndex {
                let next = str.index(after: i)
                let nextChar = str[next]
                switch nextChar {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "'": result.append("'")
                default:
                    // For unknown escapes, keep the backslash
                    result.append("\\")
                    result.append(nextChar)
                }
                i = str.index(after: next)
            } else {
                result.append(str[i])
                i = str.index(after: i)
            }
        }
        return result
    }
    
    /// Minimal YAML parser supporting the subset used in rule frontmatter:
    /// top-level keys with string values, arrays, and one level of nesting.
    static func parseSimpleYAML(_ text: String) -> [String: Any] {
        var result: [String: Any] = [:]
        let lines = text.components(separatedBy: .newlines)

        var currentKey: String?       // Top-level key being built (nested dict)
        var currentDict: [String: Any]?
        var currentList: [String]?    // Top-level list being built
        var listKey: String?
        var nestedListKey: String?    // Nested dict key that expects sub-list items

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let indentLevel = line.prefix(while: { $0 == " " }).count

            // Top-level key
            if indentLevel == 0 && trimmed.contains(":") {
                // Flush any pending nested dict or list
                if let key = currentKey, let dict = currentDict {
                    result[key] = dict
                    currentKey = nil
                    currentDict = nil
                    nestedListKey = nil
                }
                if let key = listKey, let list = currentList {
                    result[key] = list
                    listKey = nil
                    currentList = nil
                }

                let colonIdx = trimmed.firstIndex(of: ":")!
                let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let afterColon = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

                if afterColon.isEmpty {
                    currentKey = key
                    currentDict = [:]
                } else if afterColon.hasPrefix("[") && afterColon.hasSuffix("]") {
                    let inner = String(afterColon.dropFirst().dropLast())
                    let items = inner.components(separatedBy: ",").map { item in
                        let trimmed = item.trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        return unescapeYAMLString(trimmed)
                    }.filter { !$0.isEmpty }
                    result[key] = items
                } else {
                    let trimmed = afterColon.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    result[key] = unescapeYAMLString(trimmed)
                }
            } else if indentLevel > 0 && trimmed.hasPrefix("- ") {
                // List item
                let trimmedValue = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let value = unescapeYAMLString(trimmedValue)

                if let nlk = nestedListKey, currentDict != nil {
                    // Sub-list item within a nested dict key
                    var existing = currentDict?[nlk] as? [String] ?? []
                    existing.append(value)
                    currentDict?[nlk] = existing
                } else if currentList != nil {
                    currentList?.append(value)
                } else if let key = currentKey {
                    // Switch from expecting dict to list
                    currentDict = nil
                    nestedListKey = nil
                    listKey = key
                    currentKey = nil
                    currentList = [value]
                } else if listKey != nil {
                    currentList?.append(value)
                }
            } else if indentLevel > 0 && trimmed.contains(":") {
                // Nested key-value
                let colonIdx = trimmed.firstIndex(of: ":")!
                let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let afterColon = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

                if let _ = currentKey {
                    nestedListKey = nil
                    if afterColon.hasPrefix("[") && afterColon.hasSuffix("]") {
                        let inner = String(afterColon.dropFirst().dropLast())
                        let items = inner.components(separatedBy: ",").map { item in
                            let trimmed = item.trimmingCharacters(in: .whitespaces)
                                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                            return unescapeYAMLString(trimmed)
                        }.filter { !$0.isEmpty }
                        currentDict?[key] = items
                    } else if afterColon.isEmpty {
                        // Nested key with no value — expect sub-list items
                        currentDict?[key] = [] as [String]
                        nestedListKey = key
                    } else {
                        let trimmed = afterColon.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        currentDict?[key] = unescapeYAMLString(trimmed)
                    }
                }
            }
        }

        // Flush remaining
        if let key = currentKey, let dict = currentDict {
            result[key] = dict
        }
        if let key = listKey, let list = currentList {
            result[key] = list
        }

        return result
    }
}

