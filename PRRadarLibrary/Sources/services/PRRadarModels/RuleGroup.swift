import Foundation

/// A group of tasks sharing the same rule identity (name + rulesDir).
public struct RuleGroup: Identifiable, Sendable {
    public let displayName: String
    public let tasks: [RuleRequest]

    public var id: String { tasks.first?.taskId ?? "" }

    public var filter: RuleFilter {
        RuleFilter(taskIds: tasks.map(\.taskId))
    }

    public static func fromTasks(_ tasks: [RuleRequest]) -> [RuleGroup] {
        var groups: [(key: String, displayName: String, tasks: [RuleRequest])] = []
        var index: [String: Int] = [:]
        for task in tasks.sorted() {
            let key = "\(task.rule.name)\0\(task.rule.rulesDir)"
            if let i = index[key] {
                groups[i].tasks.append(task)
            } else {
                index[key] = groups.count
                groups.append((key: key, displayName: task.rule.displayName, tasks: [task]))
            }
        }
        return groups.map { RuleGroup(displayName: $0.displayName, tasks: $0.tasks) }
    }
}
