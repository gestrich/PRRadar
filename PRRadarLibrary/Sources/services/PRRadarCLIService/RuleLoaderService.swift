import Foundation
import GitSDK
import PRRadarModels

public enum RuleLoaderError: LocalizedError {
    case directoryNotFound(String)
    case notADirectory(String)
    case notAGitRepository(String)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Rules directory not found: \(path)"
        case .notADirectory(let path):
            return "Not a directory: \(path)"
        case .notAGitRepository(let path):
            return "Not a git repository: \(path)"
        }
    }
}

/// Loads and filters review rules from a directory of markdown files.
///
/// Rules are loaded once from YAML frontmatter via `ReviewRule.fromFile(_:)` and
/// filtered against file patterns and grep patterns. Uses Foundation `FileManager`
/// for directory scanning — no CLI dependency.
public struct RuleLoaderService: Sendable {
    private let gitOps: GitOperationsService

    public init(gitOps: GitOperationsService) {
        self.gitOps = gitOps
    }

    /// Load all rules from a rules directory.
    ///
    /// Recursively finds all `.md` files and parses them as rules. Files that
    /// fail to parse are skipped with a warning printed to stdout.
    ///
    /// - Parameters:
    ///   - rulesDir: Path to the directory containing rule markdown files
    /// - Returns: List of parsed `ReviewRule` instances
    public func loadAllRules(rulesDir: String) async throws -> [ReviewRule] {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: rulesDir, isDirectory: &isDir) else {
            throw RuleLoaderError.directoryNotFound(rulesDir)
        }
        guard isDir.boolValue else {
            throw RuleLoaderError.notADirectory(rulesDir)
        }

        let mdFiles = findMarkdownFiles(in: rulesDir)
        var remoteURL: String?
        var repoRoot: String?
        var branch: String?
        do {
            remoteURL = try await gitOps.getRemoteURL(path: rulesDir)
            repoRoot = try await gitOps.getRepoRoot(path: rulesDir)
            branch = try await gitOps.getCurrentBranch(path: rulesDir)
        } catch {
            // Non-fatal — rule URLs will be omitted
        }

        var rules: [ReviewRule] = []
        for filePath in mdFiles {
            let url = URL(fileURLWithPath: filePath)
            do {
                var rule = try ReviewRule.fromFile(url)
                if let remote = remoteURL, let root = repoRoot {
                    rule = ruleWithURL(rule, filePath: filePath, repoRoot: root, remoteURL: remote, branch: branch ?? "main")
                }
                rules.append(rule)
            } catch {
                print("Warning: Failed to parse rule \(filePath): \(error)")
            }
        }

        return rules
    }

    /// Filter rules that apply to a specific file path.
    public func filterRulesForFile(_ rules: [ReviewRule], filePath: String) -> [ReviewRule] {
        rules.filter { $0.appliesToFile(filePath) }
    }

    /// Filter rules applicable to a focus area.
    ///
    /// Checks both file pattern matching and grep pattern matching against
    /// the focused content (lines within the focus area bounds).
    public func filterRulesForFocusArea(_ allRules: [ReviewRule], focusArea: FocusArea) -> [ReviewRule] {
        allRules.filter { rule in
            guard rule.appliesToFile(focusArea.filePath) else { return false }

            if let grep = rule.grep, grep.hasPatterns {
                let focusedContent = focusArea.getFocusedContent()
                let changedContent = Hunk.extractChangedContent(from: focusedContent)
                guard rule.matchesDiffContent(changedContent) else { return false }
            }

            return true
        }
    }

    // MARK: - Private

    private func findMarkdownFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return [] }

        var files: [String] = []
        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(".md") {
                files.append("\(directory)/\(file)")
            }
        }
        return files.sorted()
    }

    private func ruleWithURL(
        _ rule: ReviewRule,
        filePath: String,
        repoRoot: String,
        remoteURL: String,
        branch: String
    ) -> ReviewRule {
        let normalizedRoot = repoRoot.hasSuffix("/") ? repoRoot : repoRoot + "/"
        let relativePath = filePath.hasPrefix(normalizedRoot)
            ? String(filePath.dropFirst(normalizedRoot.count))
            : filePath

        let repoBase = remoteURL
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let githubBase: String
        if repoBase.contains("github.com") {
            githubBase = repoBase
                .replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
        } else {
            githubBase = repoBase
        }

        let ruleUrl = "\(githubBase)/blob/\(branch)/\(relativePath)"

        return ReviewRule(
            name: rule.name,
            filePath: rule.filePath,
            description: rule.description,
            category: rule.category,
            focusType: rule.focusType,
            content: rule.content,
            model: rule.model,
            documentationLink: rule.documentationLink,
            relevantClaudeSkill: rule.relevantClaudeSkill,
            ruleUrl: ruleUrl,
            appliesTo: rule.appliesTo,
            grep: rule.grep,
            newCodeLinesOnly: rule.newCodeLinesOnly,
            violationRegex: rule.violationRegex,
            violationMessage: rule.violationMessage
        )
    }
}
