import Foundation
import PRRadarConfigService
import PRRadarModels

/// Pairs applicable rules with focus areas to create evaluation tasks.
///
/// For each focus area, filters rules by applicability (file patterns and grep patterns),
/// then creates an `EvaluationTaskOutput` for each (rule, focusArea) pair. Writes task
/// files to the phase-4 output directory.
public struct TaskCreatorService: Sendable {
    private let ruleLoader: RuleLoaderService
    private let gitOps: GitOperationsService

    public init(ruleLoader: RuleLoaderService, gitOps: GitOperationsService) {
        self.ruleLoader = ruleLoader
        self.gitOps = gitOps
    }

    /// Create evaluation tasks by pairing rules with focus areas.
    ///
    /// - Parameters:
    ///   - rules: All loaded review rules
    ///   - focusAreas: Focus areas to evaluate (both method and file level)
    ///   - repoPath: Path to the git repository (for blob hash lookups)
    /// - Returns: List of evaluation tasks
    public func createTasks(rules: [ReviewRule], focusAreas: [FocusArea], repoPath: String) async throws -> [EvaluationTaskOutput] {
        var blobHashCache: [String: String] = [:]
        var tasks: [EvaluationTaskOutput] = []

        for focusArea in focusAreas {
            let applicableRules = ruleLoader.filterRulesForFocusArea(rules, focusArea: focusArea)
            for rule in applicableRules {
                guard rule.focusType == focusArea.focusType else { continue }

                let filePath = focusArea.filePath
                if blobHashCache[filePath] == nil {
                    blobHashCache[filePath] = try await gitOps.getBlobHash(
                        commit: "HEAD", filePath: filePath, repoPath: repoPath
                    )
                }
                let blobHash = blobHashCache[filePath]!

                let task = EvaluationTaskOutput.from(rule: rule, focusArea: focusArea, gitBlobHash: blobHash)
                tasks.append(task)
            }
        }

        return tasks
    }

    /// Create tasks and write them to the phase-4 output directory.
    ///
    /// - Parameters:
    ///   - rules: All loaded review rules
    ///   - focusAreas: Focus areas to evaluate
    ///   - outputDir: PR-specific output directory (e.g., `<base>/<pr_number>`)
    ///   - repoPath: Path to the git repository (for blob hash lookups)
    /// - Returns: List of created evaluation tasks
    public func createAndWriteTasks(
        rules: [ReviewRule],
        focusAreas: [FocusArea],
        outputDir: String,
        repoPath: String
    ) async throws -> [EvaluationTaskOutput] {
        let tasks = try await createTasks(rules: rules, focusAreas: focusAreas, repoPath: repoPath)

        let tasksDir = "\(outputDir)/\(PRRadarPhase.tasks.rawValue)"
        try DataPathsService.ensureDirectoryExists(at: tasksDir)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for task in tasks {
            let data = try encoder.encode(task)
            let filePath = "\(tasksDir)/\(DataPathsService.dataFilePrefix)\(task.taskId).json"
            try data.write(to: URL(fileURLWithPath: filePath))
        }

        return tasks
    }
}
