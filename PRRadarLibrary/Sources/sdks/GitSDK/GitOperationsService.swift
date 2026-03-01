import CLISDK
import Foundation

public enum GitOperationsError: LocalizedError {
    case dirtyWorkingDirectory(String)
    case fetchFailed(String)
    case checkoutFailed(String)
    case diffFailed(String)
    case fileNotFound(String)
    case notARepository(String)

    public var errorDescription: String? {
        switch self {
        case .dirtyWorkingDirectory(let path):
            return "Working directory is dirty: \(path)"
        case .fetchFailed(let detail):
            return "Git fetch failed: \(detail)"
        case .checkoutFailed(let detail):
            return "Git checkout failed: \(detail)"
        case .diffFailed(let detail):
            return "Git diff failed: \(detail)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        }
    }
}

public struct GitOperationsService: Sendable {
    private let client: CLIClient

    public init(client: CLIClient) {
        self.client = client
    }

    public func checkWorkingDirectoryClean(repoPath: String) async throws {
        guard try await isGitRepository(path: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }

        let output = try await client.execute(
            GitCLI.Status(porcelain: true),
            workingDirectory: repoPath,
            printCommand: false
        )

        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GitOperationsError.dirtyWorkingDirectory(
                "Cannot proceed - uncommitted changes detected. "
                + "Commit or stash your changes, then try again."
            )
        }
    }

    public func fetchBranch(remote: String, branch: String, repoPath: String) async throws {
        guard try await isGitRepository(path: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }

        do {
            _ = try await client.execute(
                GitCLI.Fetch(remote: remote, branch: branch),
                workingDirectory: repoPath,
                printCommand: false
            )
        } catch {
            throw GitOperationsError.fetchFailed("Failed to fetch \(remote)/\(branch): \(error)")
        }
    }

    public func checkoutCommit(sha: String, repoPath: String) async throws {
        guard try await isGitRepository(path: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }

        do {
            _ = try await client.execute(
                GitCLI.Checkout(ref: sha),
                workingDirectory: repoPath,
                printCommand: false
            )
        } catch {
            throw GitOperationsError.checkoutFailed("Failed to checkout \(sha): \(error)")
        }
    }

    public func clean(repoPath: String) async throws {
        guard try await isGitRepository(path: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }

        _ = try await client.execute(
            GitCLI.Clean(args: ["-ffd"]),
            workingDirectory: repoPath,
            printCommand: false
        )
    }

    public func getBranchDiff(base: String, head: String, remote: String, repoPath: String) async throws -> String {
        guard try await isGitRepository(path: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }

        do {
            return try await client.execute(
                GitCLI.Diff(args: ["\(remote)/\(base)...\(remote)/\(head)"]),
                workingDirectory: repoPath,
                printCommand: false
            )
        } catch {
            throw GitOperationsError.diffFailed("Failed to compute diff: \(error)")
        }
    }

    public func isGitRepository(path: String) async throws -> Bool {
        let result = try await client.executeForResult(
            GitCLI.RevParse(gitDir: true),
            workingDirectory: path,
            printCommand: false
        )
        return result.isSuccess
    }

    public func getFileContent(commit: String, filePath: String, repoPath: String) async throws -> String {
        guard try await isGitRepository(path: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }

        do {
            return try await client.execute(
                GitCLI.Show(spec: "\(commit):\(filePath)"),
                workingDirectory: repoPath,
                printCommand: false
            )
        } catch {
            throw GitOperationsError.fileNotFound("File \(filePath) not found at \(commit)")
        }
    }

    public func getRepoRoot(path: String) async throws -> String {
        try await client.execute(
            GitCLI.RevParse(showToplevel: true),
            workingDirectory: path,
            printCommand: false
        )
    }

    public func getCurrentBranch(path: String) async throws -> String {
        try await client.execute(
            GitCLI.RevParse(abbrevRef: true, ref: "HEAD"),
            workingDirectory: path,
            printCommand: false
        )
    }

    public func getMergeBase(commit1: String, commit2: String, repoPath: String) async throws -> String {
        guard try await isGitRepository(path: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }

        return try await client.execute(
            GitCLI.MergeBase(commits: [commit1, commit2]),
            workingDirectory: repoPath,
            printCommand: false
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func getRemoteURL(path: String) async throws -> String {
        try await client.execute(
            GitCLI.Remote(args: ["get-url", "origin"]),
            workingDirectory: path,
            printCommand: false
        )
    }

    public func getBlobHash(commit: String, filePath: String, repoPath: String) async throws -> String {
        let output = try await client.execute(
            GitCLI.RevParse(ref: "\(commit):\(filePath)"),
            workingDirectory: repoPath,
            printCommand: false
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Synchronous Git Operations

/// Runs `git diff --no-index` on two text strings, returning a unified diff with relabeled paths.
///
/// This is synchronous because `git diff --no-index` operates on temp files outside any repository,
/// and callers (e.g. `RediffFunction`) require a synchronous interface.
public func gitDiffNoIndex(oldText: String, newText: String, oldLabel: String, newLabel: String) throws -> String {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let oldPath = tmpDir.appendingPathComponent("old.txt")
    let newPath = tmpDir.appendingPathComponent("new.txt")
    try oldText.write(to: oldPath, atomically: true, encoding: .utf8)
    try newText.write(to: newPath, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["diff", "--no-index", "--no-color", oldPath.path, newPath.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    var raw = String(data: data, encoding: .utf8) ?? ""

    if raw.isEmpty { return "" }

    let oldRel = String(oldPath.path.dropFirst())
    let newRel = String(newPath.path.dropFirst())
    raw = raw.replacingOccurrences(of: "a/\(oldRel)", with: "a/\(oldLabel)")
    raw = raw.replacingOccurrences(of: "b/\(newRel)", with: "b/\(newLabel)")

    return raw
}
