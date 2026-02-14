import CLISDK
import Foundation
import PRRadarConfigService
import PRRadarMacSDK

public enum GitHubServiceError: Error, LocalizedError {
    case missingToken
    case cannotParseRemoteURL(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No GitHub token found. Set GITHUB_TOKEN env var or store credentials in the Keychain via 'config credentials add'."
        case .cannotParseRemoteURL(let url):
            return "Cannot parse owner/repo from git remote URL: \(url)"
        }
    }
}

public struct GitHubServiceFactory: Sendable {
    public static func create(repoPath: String, tokenOverride: String? = nil) async throws -> (gitHub: GitHubService, gitOps: GitOperationsService) {
        let env = PRRadarEnvironment.build()
        guard let token = tokenOverride ?? env["GITHUB_TOKEN"] else {
            throw GitHubServiceError.missingToken
        }

        let gitOps = createGitOps()
        let remoteURL = try await gitOps.getRemoteURL(path: repoPath)

        guard let (owner, repo) = GitHubService.parseOwnerRepo(from: remoteURL) else {
            throw GitHubServiceError.cannotParseRemoteURL(remoteURL)
        }

        let octokitClient = OctokitClient(token: token)
        let gitHub = GitHubService(octokitClient: octokitClient, owner: owner, repo: repo)

        return (gitHub, gitOps)
    }

    public static func createGitOps() -> GitOperationsService {
        GitOperationsService(client: CLIClient())
    }
}
