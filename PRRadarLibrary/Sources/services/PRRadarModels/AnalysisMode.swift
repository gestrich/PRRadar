import Foundation

public enum AnalysisMode: String, Sendable, CaseIterable {
    case all
    case regexOnly = "regex"
    case aiOnly = "ai"

    public func matches(_ task: RuleRequest) -> Bool {
        switch self {
        case .all: return true
        case .regexOnly: return task.rule.isRegexOnly
        case .aiOnly: return !task.rule.isRegexOnly
        }
    }
}
