import Foundation
import PRRadarModels

public struct PostSingleCommentUseCase: Sendable {

    private let environment: [String: String]

    public init(environment: [String: String]) {
        self.environment = environment
    }

    public func execute(
        repoSlug: String,
        prNumber: String,
        filePath: String,
        lineNumber: Int?,
        commitSHA: String,
        commentBody: String
    ) async throws -> Bool {
        let ghPath = resolveGhPath()

        if let lineNumber {
            return try await postInlineComment(
                ghPath: ghPath,
                repoSlug: repoSlug,
                prNumber: prNumber,
                filePath: filePath,
                lineNumber: lineNumber,
                commitSHA: commitSHA,
                commentBody: commentBody
            )
        } else {
            return try await postGeneralComment(
                ghPath: ghPath,
                repoSlug: repoSlug,
                prNumber: prNumber,
                commentBody: commentBody
            )
        }
    }

    private func postInlineComment(
        ghPath: String,
        repoSlug: String,
        prNumber: String,
        filePath: String,
        lineNumber: Int,
        commitSHA: String,
        commentBody: String
    ) async throws -> Bool {
        let endpoint = "repos/\(repoSlug)/pulls/\(prNumber)/comments"
        let arguments = [
            "api", endpoint,
            "-f", "body=\(commentBody)",
            "-f", "path=\(filePath)",
            "-f", "side=RIGHT",
            "-f", "commit_id=\(commitSHA)",
            "-F", "line=\(lineNumber)",
        ]
        return try await runGh(ghPath: ghPath, arguments: arguments)
    }

    private func postGeneralComment(
        ghPath: String,
        repoSlug: String,
        prNumber: String,
        commentBody: String
    ) async throws -> Bool {
        let endpoint = "repos/\(repoSlug)/issues/\(prNumber)/comments"
        let arguments = [
            "api", endpoint,
            "-f", "body=\(commentBody)",
        ]
        return try await runGh(ghPath: ghPath, arguments: arguments)
    }

    private func runGh(ghPath: String, arguments: [String]) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = arguments

            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                env[key] = value
            }
            process.environment = env

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func resolveGhPath() -> String {
        if let ghEnv = environment["GH_PATH"], !ghEnv.isEmpty {
            return ghEnv
        }
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/gh") {
            return "/opt/homebrew/bin/gh"
        }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/gh") {
            return "/usr/local/bin/gh"
        }
        return "/usr/bin/gh"
    }
}
