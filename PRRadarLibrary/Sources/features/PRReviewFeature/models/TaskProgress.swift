import PRRadarModels

public enum TaskProgress: Sendable {
    case prompt(text: String)
    case output(text: String)
    case toolUse(name: String)
    case completed(result: RuleEvaluationResult)
}
