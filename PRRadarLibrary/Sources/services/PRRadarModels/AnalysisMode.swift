import Foundation

public enum AnalysisMode: String, Sendable, CaseIterable {
    case all
    case regexOnly = "regex"
    case scriptOnly = "script"
    case aiOnly = "ai"

    public func matches(_ task: RuleRequest) -> Bool {
        switch self {
        case .all: return true
        case .regexOnly: return task.rule.analysisType == .regex
        case .scriptOnly: return task.rule.analysisType == .script
        case .aiOnly: return task.rule.analysisType == .ai
        }
    }
}
