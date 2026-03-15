## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules for code placement |
| `/swift-testing` | Test style guide |

## Background

PRRadar's GitHub Actions workflow uses a **GitHub App** (via `actions/create-github-app-token@v2`) to post PR comments under the PR Radar bot identity. This requires an App ID and a PEM private key, which are stored as GitHub Actions secrets/variables.

Currently, when running locally (CLI or Mac app), PRRadar can only authenticate with a **Personal Access Token (PAT)**. This means local comment posting shows up under Bill's personal GitHub account, not the PR Radar bot.

GitHub App authentication works like this:
1. Sign a **JWT** using the App ID + private key (RS256 algorithm, 10-minute expiry)
2. Exchange the JWT for a short-lived **installation access token** via `POST /app/installations/{installation_id}/access_tokens`
3. Use that installation token as a Bearer token (same as a PAT)

The existing credential system already supports storing secrets in the macOS Keychain via `SecurityCLIKeychainStore` with the `{account}/{type}` key format. We'll extend this to store GitHub App credentials (App ID, installation ID, and private key PEM) alongside existing token types.

Since the installation token is short-lived (1 hour), we'll generate it on-demand in `GitHubServiceFactory` when the credential account is configured for app auth.

## Phases

## - [x] Phase 1: Add GitHub App credential storage

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add new credential types to `SettingsService` for GitHub App auth:
- `github-app-id` — The GitHub App's numeric ID
- `github-app-installation-id` — The installation ID for the target org/repo
- `github-app-private-key` — The PEM private key content

Files to modify:
- `Sources/services/PRRadarConfigService/SettingsService.swift` — Add new type constants (`gitHubAppIdType`, `gitHubAppInstallationIdType`, `gitHubAppPrivateKeyType`) and save/load/remove methods for each
- `Sources/apps/MacCLI/Commands/CredentialsCommand.swift` — Add `--app-id`, `--installation-id`, `--private-key-path` options to the `add` subcommand. The `--private-key-path` flag reads the PEM file and stores its contents in the keychain
- `Sources/features/PRReviewFeature/usecases/SaveCredentialsUseCase.swift` — Extend to handle app credential fields
- `Sources/features/PRReviewFeature/usecases/LoadCredentialStatusUseCase.swift` — Report whether app credentials are configured

The private key PEM content will be stored directly in the keychain as a string (same as tokens). The PEM file path is only used at CLI input time.

## - [x] Phase 2: JWT generation and token exchange

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a service that generates GitHub App installation tokens:

1. **JWT signing** — Create a `GitHubAppTokenService` in `PRRadarCLIService` (or a new SDK) that:
   - Builds a JWT payload: `iss` = App ID, `iat` = now - 60s, `exp` = now + 600s
   - Signs it with RS256 using the PEM private key
   - On macOS, use `Security.framework` (`SecKeyCreateWithData` to load the PEM, `SecKeyCreateSignedDataBlock` or `SecKeyCreateSignature` for RS256)
   - Alternatively, use `CryptoKit` or `swift-crypto` (already conditionally imported for Linux) for cross-platform support

2. **Token exchange** — Call `POST https://api.github.com/app/installations/{installation_id}/access_tokens` with the JWT as Bearer auth, parse the `token` field from the response

Files to create/modify:
- New: `Sources/services/PRRadarCLIService/GitHubAppTokenService.swift` — JWT generation + token exchange
- The service should be a simple struct with a single `func generateInstallationToken(appId: String, installationId: String, privateKeyPEM: String) async throws -> String`

## - [x] Phase 3: Integrate into credential resolution

**Skills to read**: `/swift-app-architecture:swift-architecture`

Update `CredentialResolver` and `GitHubServiceFactory` to support app-based auth:

- `CredentialResolver` — Add `getGitHubAppCredentials() -> (appId: String, installationId: String, privateKey: String)?` that checks keychain for app credentials on the account
- `GitHubServiceFactory.create()` — After resolving credentials:
  - If a PAT is found (existing behavior), use it directly
  - If GitHub App credentials are found instead, call `GitHubAppTokenService.generateInstallationToken()` to get a short-lived token, then pass that to `OctokitClient`
  - If both exist, prefer the App token (so comments post under bot identity)
  - Also support `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY` environment variables for CI flexibility

Files to modify:
- `Sources/services/PRRadarConfigService/CredentialResolver.swift`
- `Sources/services/PRRadarCLIService/GitHubServiceFactory.swift`

## - [x] Phase 4: UI support for app credentials

Update the Mac app's credential management views to support GitHub App auth:

- `CredentialManagementView` / edit sheet — Add fields for App ID, Installation ID, and private key PEM (textarea or file picker)
- `SettingsModel` — Extend `saveCredentials()` and `credentialStatus()` to include app credential fields
- `CredentialStatus` — Add `hasGitHubAppId`, `hasGitHubAppInstallationId`, `hasGitHubAppPrivateKey` booleans

Files to modify:
- `Sources/apps/MacApp/UI/Settings/CredentialManagementView.swift`
- `Sources/apps/MacApp/Models/SettingsModel.swift`
- `Sources/features/PRReviewFeature/usecases/LoadCredentialStatusUseCase.swift`

## - [x] Phase 5: Validation

**Skills to read**: `/swift-testing`

- Add unit tests for JWT generation (verify the JWT header/payload structure, not the actual signature)
- Add unit tests for `CredentialResolver` app credential lookup (extend existing `CredentialResolverTests`)
- Add unit tests for `GitHubServiceFactory` preferring app token over PAT
- Manual test: Store a real GitHub App private key via CLI, run `swift run PRRadarMacCLI comment <PR> --config <config>` and verify the comment is posted under the bot identity
- Run `swift test` to ensure no regressions
