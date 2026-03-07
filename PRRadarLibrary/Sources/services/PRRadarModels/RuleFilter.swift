import Foundation

/// Filter criteria for selective analysis of tasks.
///
/// All fields are optional — nil means "no filter" for that dimension.
/// When multiple fields are set, they combine with AND logic.
public struct RuleFilter: Sendable {
    public let filePath: String?
    public let focusAreaId: String?
    public let ruleNames: [String]?
    public let ruleFilePaths: [String]?

    public init(filePath: String? = nil, focusAreaId: String? = nil, ruleNames: [String]? = nil, ruleFilePaths: [String]? = nil) {
        self.filePath = filePath
        self.focusAreaId = focusAreaId
        self.ruleNames = ruleNames
        self.ruleFilePaths = ruleFilePaths
    }

    /// Returns true if the given task matches all non-nil filter criteria.
    public func matches(_ task: RuleRequest) -> Bool {
        if let filePath, task.focusArea.filePath != filePath {
            return false
        }
        if let focusAreaId, task.focusArea.focusId != focusAreaId {
            return false
        }
        if let ruleNames, !ruleNames.contains(task.rule.name) {
            return false
        }
        if let ruleFilePaths {
            let matchesAny = ruleFilePaths.contains { path in
                let pathName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let pathDir = task.rule.rulesDir.hasSuffix("/") ? task.rule.rulesDir : task.rule.rulesDir + "/"
                return pathName == task.rule.name && path.hasPrefix(pathDir)
            }
            if !matchesAny { return false }
        }
        return true
    }

    /// True when no filter criteria are set.
    public var isEmpty: Bool {
        filePath == nil && focusAreaId == nil && ruleNames == nil && ruleFilePaths == nil
    }
}
