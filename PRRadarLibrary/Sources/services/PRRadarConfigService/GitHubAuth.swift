import Foundation

public enum GitHubAuth: Sendable {
    case token(String)
    case app(appId: String, installationId: String, privateKeyPEM: String)
}
