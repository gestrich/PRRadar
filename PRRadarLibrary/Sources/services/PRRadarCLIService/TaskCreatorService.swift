import CryptoKit
import Foundation
import PRRadarConfigService
import PRRadarModels

/// Pairs applicable rules with focus areas to create evaluation tasks.
///
/// For each focus area, filters rules by applicability (file patterns and grep patterns),
/// then creates an `AnalysisTaskOutput` for each (rule, focusArea) pair. Writes task
/// files to the prepare phase output directory.
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
    ///   - commit: The commit hash for source file blob lookups
    ///   - rulesDir: Path to the rules directory (for rule blob hash lookups)
    /// - Returns: List of evaluation tasks
    public func createTasks(rules: [ReviewRule], focusAreas: [FocusArea], repoPath: String, commit: String, rulesDir: String? = nil) async throws -> [AnalysisTaskOutput] {
        var blobHashCache: [String: String] = [:]
        var ruleBlobHashCache: [String: String] = [:]
        var tasks: [AnalysisTaskOutput] = []

        let rulesRepoInfo = await resolveRulesRepoInfo(rulesDir: rulesDir)

        for focusArea in focusAreas {
            let applicableRules = ruleLoader.filterRulesForFocusArea(rules, focusArea: focusArea)
            for rule in applicableRules {
                guard rule.focusType == focusArea.focusType else { continue }

                let filePath = focusArea.filePath
                if blobHashCache[filePath] == nil {
                    do {
                        blobHashCache[filePath] = try await gitOps.getBlobHash(
                            commit: commit, filePath: filePath, repoPath: repoPath
                        )
                    } catch {
                        blobHashCache[filePath] = "\(commit):\(filePath)"
                    }
                }
                let blobHash = blobHashCache[filePath]!

                let ruleBlobHash = await resolveRuleBlobHash(
                    rule: rule, rulesRepoInfo: rulesRepoInfo, cache: &ruleBlobHashCache
                )

                let task = AnalysisTaskOutput.from(rule: rule, focusArea: focusArea, gitBlobHash: blobHash, ruleBlobHash: ruleBlobHash)
                tasks.append(task)
            }
        }

        return tasks
    }

    /// Create tasks and write them to the prepare phase output directory.
    ///
    /// - Parameters:
    ///   - rules: All loaded review rules
    ///   - focusAreas: Focus areas to evaluate
    ///   - outputDir: PR-specific output directory (e.g., `<base>/<pr_number>`)
    ///   - repoPath: Path to the git repository (for blob hash lookups)
    ///   - commit: The commit hash for source file blob lookups
    ///   - rulesDir: Path to the rules directory (for rule blob hash lookups)
    /// - Returns: List of created evaluation tasks
    public func createAndWriteTasks(
        rules: [ReviewRule],
        focusAreas: [FocusArea],
        outputDir: String,
        repoPath: String,
        commit: String,
        rulesDir: String? = nil
    ) async throws -> [AnalysisTaskOutput] {
        let tasks = try await createTasks(rules: rules, focusAreas: focusAreas, repoPath: repoPath, commit: commit, rulesDir: rulesDir)

        let tasksDir = "\(outputDir)/\(PRRadarPhase.prepare.rawValue)/\(DataPathsService.prepareTasksSubdir)"
        try DataPathsService.ensureDirectoryExists(at: tasksDir)

        // Remove stale task files from previous runs before writing new ones
        let fm = FileManager.default
        if let existing = try? fm.contentsOfDirectory(atPath: tasksDir) {
            for file in existing where file.hasPrefix(DataPathsService.dataFilePrefix) {
                try? fm.removeItem(atPath: "\(tasksDir)/\(file)")
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for task in tasks {
            let data = try encoder.encode(task)
            let filePath = "\(tasksDir)/\(DataPathsService.dataFilePrefix)\(task.taskId).json"
            try data.write(to: URL(fileURLWithPath: filePath))
        }

        return tasks
    }

    // MARK: - Rule Blob Hash Resolution

    private struct RulesRepoInfo {
        let repoRoot: String
    }

    private func resolveRulesRepoInfo(rulesDir: String?) async -> RulesRepoInfo? {
        guard let rulesDir else { return nil }
        do {
            guard try await gitOps.isGitRepository(path: rulesDir) else { return nil }
            let repoRoot = try await gitOps.getRepoRoot(path: rulesDir)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return RulesRepoInfo(repoRoot: repoRoot)
        } catch {
            return nil
        }
    }

    private func resolveRuleBlobHash(
        rule: ReviewRule,
        rulesRepoInfo: RulesRepoInfo?,
        cache: inout [String: String]
    ) async -> String? {
        let ruleFilePath = rule.filePath
        if let cached = cache[ruleFilePath] { return cached }

        let hash: String?
        if let info = rulesRepoInfo {
            let normalizedRoot = info.repoRoot.hasSuffix("/") ? info.repoRoot : info.repoRoot + "/"
            if ruleFilePath.hasPrefix(normalizedRoot) {
                let relativePath = String(ruleFilePath.dropFirst(normalizedRoot.count))
                do {
                    hash = try await gitOps.getBlobHash(
                        commit: "HEAD", filePath: relativePath, repoPath: info.repoRoot
                    )
                } catch {
                    hash = contentHash(filePath: ruleFilePath)
                }
            } else {
                hash = contentHash(filePath: ruleFilePath)
            }
        } else {
            hash = contentHash(filePath: ruleFilePath)
        }

        if let hash { cache[ruleFilePath] = hash }
        return hash
    }

    private func contentHash(filePath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: filePath) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
