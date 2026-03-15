import Foundation

public struct CredentialStatus: Sendable {
    public let account: String
    public let gitHubAuth: GitHubAuthStatus
    public let hasAnthropicKey: Bool

    public init(account: String, gitHubAuth: GitHubAuthStatus, hasAnthropicKey: Bool) {
        self.account = account
        self.gitHubAuth = gitHubAuth
        self.hasAnthropicKey = hasAnthropicKey
    }
}

public enum GitHubAuthStatus: Sendable {
    case none
    case token
    case app
}
