import CLISDK
import Foundation
import PRRadarConfigService
import PRRadarMacSDK

public enum GitHubServiceError: Error {
    case missingToken
    case cannotParseRemoteURL(String)
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
