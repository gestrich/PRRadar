#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import GitSDK
import PRRadarConfigService
import PRRadarModels

/// Pairs applicable rules with focus areas to create evaluation tasks.
///
/// For each focus area, filters rules by applicability (file patterns and grep patterns),
/// then creates an `RuleRequest` for each (rule, focusArea) pair. Writes task
/// files to the prepare phase output directory.
public struct TaskCreatorService: Sendable {
    private let ruleLoader: RuleLoaderService
    private let gitOps: GitOperationsService
    private let historyProvider: GitHistoryProvider

    public init(ruleLoader: RuleLoaderService, gitOps: GitOperationsService, historyProvider: GitHistoryProvider) {
        self.ruleLoader = ruleLoader
        self.gitOps = gitOps
        self.historyProvider = historyProvider
    }

    /// Create evaluation tasks by pairing rules with focus areas.
    ///
    /// - Parameters:
    ///   - rules: All loaded review rules
    ///   - focusAreas: Focus areas to evaluate (both method and file level)
    ///   - prDiff: Unified diff data (hunks for grep matching, commit hash for blob lookups)
    ///   - rulesDir: Path to the rules directory (for rule blob hash lookups)
    /// - Returns: List of evaluation tasks
    public func createTasks(rules: [ReviewRule], focusAreas: [FocusArea], prDiff: PRDiff, rulesDir: String) async throws -> [RuleRequest] {
        let commit = prDiff.commitHash
        let deletedFiles = prDiff.toGitDiff().deletedFiles
        var blobHashCache: [String: String] = [:]
        var ruleBlobHashCache: [String: String] = [:]
        var tasks: [RuleRequest] = []

        let rulesRepoInfo = await resolveRulesRepoInfo(rulesDir: rulesDir)

        for focusArea in focusAreas {
            let applicableRules = ruleLoader.filterRulesForFocusArea(rules, focusArea: focusArea, prDiff: prDiff)
            for rule in applicableRules {
                guard rule.focusType == focusArea.focusType else { continue }

                let filePath = focusArea.filePath
                if blobHashCache[filePath] == nil {
                    if deletedFiles.contains(filePath) {
                        blobHashCache[filePath] = "\(commit):deleted:\(filePath)"
                    } else {
                        do {
                            blobHashCache[filePath] = try await historyProvider.getBlobHash(
                                commit: commit, filePath: filePath
                            )
                        } catch {
                            blobHashCache[filePath] = "\(commit):\(filePath)"
                        }
                    }
                }
                let blobHash = blobHashCache[filePath]!

                let ruleBlobHash = try await resolveRuleBlobHash(
                    rule: rule, rulesRepoInfo: rulesRepoInfo, cache: &ruleBlobHashCache
                )

                let task = RuleRequest.from(rule: rule, focusArea: focusArea, gitBlobHash: blobHash, ruleBlobHash: ruleBlobHash, rulesDir: rulesDir)
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
    ///   - prDiff: Unified diff data (hunks for grep matching, commit hash for blob lookups)
    ///   - outputDir: The prepare phase directory (e.g., `<base>/<pr_number>/analysis/<commit>/prepare/`)
    ///   - rulesDir: Path to the rules directory (for rule blob hash lookups)
    /// - Returns: List of created evaluation tasks
    public func createAndWriteTasks(
        rules: [ReviewRule],
        focusAreas: [FocusArea],
        prDiff: PRDiff,
        outputDir: String,
        rulesDir: String
    ) async throws -> [RuleRequest] {
        let tasks = try await createTasks(rules: rules, focusAreas: focusAreas, prDiff: prDiff, rulesDir: rulesDir)

        let tasksDir = "\(outputDir)/\(DataPathsService.prepareTasksSubdir)"
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
    ) async throws -> String {
        let ruleFilePath = rule.filePath
        if let cached = cache[ruleFilePath] { return cached }

        let hash: String
        if let info = rulesRepoInfo {
            let normalizedRoot = info.repoRoot.hasSuffix("/") ? info.repoRoot : info.repoRoot + "/"
            if ruleFilePath.hasPrefix(normalizedRoot) {
                let relativePath = String(ruleFilePath.dropFirst(normalizedRoot.count))
                do {
                    hash = try await gitOps.getBlobHash(
                        commit: "HEAD", filePath: relativePath, repoPath: info.repoRoot
                    )
                } catch {
                    hash = try contentHash(filePath: ruleFilePath)
                }
            } else {
                hash = try contentHash(filePath: ruleFilePath)
            }
        } else {
            hash = try contentHash(filePath: ruleFilePath)
        }

        cache[ruleFilePath] = hash
        return hash
    }

    private struct RuleFileNotFound: Error, CustomStringConvertible {
        let path: String
        var description: String { "Rule file not found: \(path)" }
    }

    private func contentHash(filePath: String) throws -> String {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            throw RuleFileNotFound(path: filePath)
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
