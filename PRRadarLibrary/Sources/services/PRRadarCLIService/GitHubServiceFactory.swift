import CLISDK
import Foundation
import GitHubSDK
import GitSDK
import PRRadarConfigService

public enum GitHubServiceError: Error, LocalizedError {
    case missingToken
    case cannotParseRemoteURL(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No GitHub token found. Set GITHUB_TOKEN env var, add to .env file, or store credentials in the Keychain via 'config credentials add'."
        case .cannotParseRemoteURL(let url):
            return "Cannot parse owner/repo from git remote URL: \(url)"
        }
    }
}

public struct GitHubServiceFactory: Sendable {
    public static func create(repoPath: String, githubAccount: String) async throws -> (gitHub: GitHubService, gitOps: GitOperationsService) {
        let token = try await resolveToken(githubAccount: githubAccount)

        let gitOps = createGitOps(gitHubToken: token)
        let remoteURL = try await gitOps.getRemoteURL(path: repoPath)

        guard let (owner, repo) = GitHubService.parseOwnerRepo(from: remoteURL) else {
            throw GitHubServiceError.cannotParseRemoteURL(remoteURL)
        }

        let octokitClient = OctokitClient(token: token)
        let gitHub = GitHubService(octokitClient: octokitClient, owner: owner, repo: repo)

        return (gitHub, gitOps)
    }

    public static func createHistoryProvider(
        diffSource: DiffSource,
        gitHub: GitHubService,
        gitOps: GitOperationsService,
        repoPath: String,
        prNumber: Int,
        baseBranch: String,
        headBranch: String
    ) -> GitHistoryProvider {
        switch diffSource {
        case .git:
            return LocalGitHistoryProvider(gitOps: gitOps, repoPath: repoPath, baseBranch: baseBranch, headBranch: headBranch)
        case .githubAPI:
            return GitHubAPIHistoryProvider(gitHub: gitHub, prNumber: prNumber)
        }
    }

    public static func createGitOps(gitHubToken: String? = nil) -> GitOperationsService {
        let environment: [String: String]? = gitHubToken.map { ["GH_TOKEN": $0] }
        return GitOperationsService(client: CLIClient(printOutput: false), environment: environment)
    }

    public static func createGitOps(githubAccount: String) async throws -> GitOperationsService {
        let token = try await resolveToken(githubAccount: githubAccount)
        return createGitOps(gitHubToken: token)
    }

    public static func resolveToken(githubAccount: String) async throws -> String {
        let resolver = CredentialResolver(settingsService: SettingsService(), githubAccount: githubAccount)
        guard let auth = resolver.getGitHubAuth() else {
            throw GitHubServiceError.missingToken
        }
        switch auth {
        case .token(let pat):
            return pat
        case .app(let appId, let installationId, let privateKeyPEM):
            return try await GitHubAppTokenService().generateInstallationToken(
                appId: appId, installationId: installationId, privateKeyPEM: privateKeyPEM
            )
        }
    }
}
