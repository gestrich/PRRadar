import Foundation

public struct CredentialStatus: Sendable {
    public let account: String
    public let hasGitHubToken: Bool
    public let hasAnthropicKey: Bool

    public init(account: String, hasGitHubToken: Bool, hasAnthropicKey: Bool) {
        self.account = account
        self.hasGitHubToken = hasGitHubToken
        self.hasAnthropicKey = hasAnthropicKey
    }
}
