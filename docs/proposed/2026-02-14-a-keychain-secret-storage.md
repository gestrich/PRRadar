## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules — layer placement for KeychainService, CredentialResolver, and dependency flow |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns — credential account UI in MacApp settings |
| `swift-testing` | Test style guide — unit tests for KeychainService and CredentialResolver |

## Background

PRRadar currently stores secrets (GitHub token and Anthropic API key) in plaintext:

- **GitHub token**: Stored in `~/Library/Application Support/PRRadar/settings.json` as part of per-repo `RepoConfiguration`, also resolved from `GITHUB_TOKEN` env var or `.env` file.
- **Anthropic API key**: Resolved only from `ANTHROPIC_API_KEY` env var or `.env` file — passed to the Python subprocess via `PRRadarEnvironment.build()`.

Storing tokens in a plaintext JSON file is a security concern. macOS provides the Keychain for exactly this purpose — encrypted at rest, unlocked with user login.

### Library Choice: Valet (by Square)

Apple does not offer a modern Swift-native Keychain API beyond the raw C-based `Security` framework (`SecItemAdd`, `SecItemCopyMatching`, etc.). A wrapper is needed.

**Valet** ([square/Valet](https://github.com/square/Valet)) is the recommended choice:
- **Swift 6 language mode** — explicitly declared in `Package.swift` with `.swiftLanguageMode(.v6)`, audited for strict concurrency and `Sendable`
- **Corporate backing** — maintained by Square/Block, 4,100+ stars, 10+ years of history
- **Full macOS support** — macOS 10.13+, with migration utilities for Catalina Keychain changes
- **Thread-safe by design** — aligns with Swift Concurrency
- **Secure Enclave support** — available if needed in the future

Alternatives considered:
- **KeychainAccess** (~8,200 stars) — most popular but no Swift 6 language mode, low maintenance activity
- **KeychainSwift** (~3,000 stars) — `clear()` and sync broken on macOS, not suitable
- **SwiftSecurity** (~300 stars) — most modern API, but solo maintainer and small community

### Credential Account Model

Secrets are stored in the Keychain under named **credential accounts**. A credential account groups a GitHub token and an Anthropic API key together. Repo configurations reference a credential account by name instead of storing raw tokens.

### Keychain Storage Design

Uses `kSecClassGenericPassword` (via Valet) with a single Valet identifier and structured keys:

- **Valet Identifier:** `com.gestrich.PRRadar` (bundle ID convention for the `kSecAttrService`)
- **Accessibility:** `.whenUnlocked` — tokens only accessible when user is logged in
- **Key pattern:** `{account}/{credential-type}` — the account name and credential type are encoded into the Valet key (maps to `kSecAttrAccount`)
- **No iCloud sync** — API tokens are device-specific; standard Valet (not `iCloudValet`)

Example Keychain entries for credential account "work":

| Valet Key (kSecAttrAccount) | Value |
|---|---|
| `work/github-token` | `ghp_abc123...` |
| `work/anthropic-api-key` | `sk-ant-...` |

And for credential account "personal":

| Valet Key (kSecAttrAccount) | Value |
|---|---|
| `personal/github-token` | `ghp_yyy...` |
| `personal/anthropic-api-key` | `sk-ant-yyy...` |

Account enumeration uses Valet's `allKeys()` method, parsing the `{account}/` prefix to derive the list of distinct credential accounts. Non-secret metadata (credential account names, repo configs) stays in `settings.json` — the Keychain stores only actual secrets.

A repo config in `settings.json` stores only the account name:
```json
{
  "name": "my-repo",
  "repoPath": "/path/to/repo",
  "credentialAccount": "work"
}
```

**Note:** Valet does not expose `kSecAttrLabel` or `kSecAttrDescription`, so items in Keychain Access will show auto-generated names rather than human-friendly labels. This is an acceptable tradeoff for Valet's cleaner API, thread safety, and automatic data protection keychain usage.

### Token Resolution Priority

For both GitHub token and Anthropic API key:

1. Environment variable (`GITHUB_TOKEN` / `ANTHROPIC_API_KEY`) — for CI/GitHub Actions and explicit overrides
2. macOS Keychain — looked up via the credential account name from the repo config (or a default account if none specified)

The `.env` file loading (`PRRadarEnvironment.loadDotEnv()`) is preserved — it feeds into step 1 since `.env` values are loaded into the environment dictionary.

The `--github-token` CLI flag is removed for parity between both secrets.

### Keychain Sharing Between MacApp and CLI

Both executables run as the same macOS user and access the same user Keychain. Valet uses `kSecClassGenericPassword` keyed by a service name — both MacApp and CLI use the same Valet identifier (`com.gestrich.PRRadar`) and read/write the same items. No special entitlements or configuration needed.

## Phases

## - [x] Phase 1: Add Valet Dependency and Create KeychainService

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Generic keychain access (`KeychainStoring` protocol + `ValetKeychainStore`) placed at SDK layer; app-specific credential methods added to existing `SettingsService` in Services layer rather than a separate service

**Skills to read**: `swift-app-architecture:swift-architecture`

Add Valet as a Swift package dependency and create a `KeychainService` in the Services layer (`PRRadarConfigService`). Per the architecture, Services hold configuration persistence and auth tokens — this is the correct layer for Keychain access.

**Tasks:**
- Add Valet dependency to `Package.swift`
- Add Valet as a dependency of the `PRRadarConfigService` target
- Create `KeychainService.swift` in `Sources/services/PRRadarConfigService/`
- `KeychainService` should be a `Sendable` struct (or final class) wrapping a `Valet` instance
- Use `Valet.valet(with: Identifier(nonEmpty: "com.gestrich.PRRadar")!, accessibility: .whenUnlocked)` — bundle ID convention, `.whenUnlocked` accessibility, no iCloud sync
- Provide account-based methods:
  - `saveGitHubToken(_:account:)`, `loadGitHubToken(account:)`, `removeGitHubToken(account:)`
  - `saveAnthropicKey(_:account:)`, `loadAnthropicKey(account:)`, `removeAnthropicKey(account:)`
  - `removeCredentials(account:)` — removes both tokens for an account
  - `listAccounts()` — uses Valet's `allKeys()`, parses `{account}/` prefix to derive distinct credential account names
- Keychain keys follow the pattern: `{account}/github-token`, `{account}/anthropic-api-key` (maps to `kSecAttrAccount`)
- A `nil` or empty account name uses `"default"` as the account name
- Write unit tests for the service

## - [x] Phase 2: Add Credential Account to RepoConfiguration

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Removed `githubToken` from both `RepoConfiguration` (persisted) and `PRRadarConfig` (runtime); replaced with `credentialAccount: String?` on `RepoConfiguration`; token resolution now deferred to `GitHubServiceFactory` (env var only until Phase 3 adds Keychain lookup)

**Skills to read**: `swift-app-architecture:swift-architecture`

Update `RepoConfiguration` to reference a credential account name instead of storing a raw GitHub token.

**Tasks:**
- Add `credentialAccount: String?` property to `RepoConfiguration`
- Remove `githubToken: String?` property from `RepoConfiguration`
- Remove `githubToken` from `PRRadarConfig`
- No backwards compatibility needed — old JSON files with `githubToken` can be deleted and recreated
- Update `presentableDescription` to show the credential account name (if set)
- Remove the `--github-token` CLI flag from `CLIOptions` and `RunAllCommand`
- Update all call sites that pass `config.githubToken` through the system

## - [x] Phase 3: Integrate Keychain into Token Resolution

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: `CredentialResolver` placed in Services layer (PRRadarConfigService) for token resolution; `credentialAccount` threaded through `PRRadarConfig` so use cases and factory methods resolve credentials via the config they already hold; `PRRadarEnvironment.build()` injects Keychain secrets into subprocess environment for the Python agent

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a centralized token resolution path that both CLI and MacApp use.

**Tasks:**
- Create `CredentialResolver` in `PRRadarConfigService` — a service that resolves tokens given an optional credential account name:
  - `resolveGitHubToken(account:)` → checks env var `GITHUB_TOKEN` first, then Keychain for the account
  - `resolveAnthropicKey(account:)` → checks env var `ANTHROPIC_API_KEY` first, then Keychain for the account
- Update `GitHubServiceFactory.create()` to use `CredentialResolver` instead of receiving a raw token. It takes a `credentialAccount: String?` parameter instead of `tokenOverride: String?`
- Update `PRRadarEnvironment.build()` to inject `ANTHROPIC_API_KEY` from Keychain (via `CredentialResolver`) if not already in the environment. Needs the credential account name passed in.
- Update `resolveConfig()` in `PRRadarMacCLI.swift` — resolve the credential account from the repo config, pass it through
- Update the error message in `GitHubServiceError.missingToken` to mention Keychain as a source
- Update all use cases that call `GitHubServiceFactory.create()` to pass the credential account

## - [x] Phase 4: Add Credential Management UI to MacApp

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: MV pattern with @Observable SettingsModel owning credential state; credential use cases in Features layer following existing SaveConfigurationUseCase pattern; SecureField for token entry; masked status display (stored/not set) without revealing raw tokens

**Skills to read**: `swift-app-architecture:swift-swiftui`

The repo config editor already has a `githubAccount` text field (added in earlier phases). What's missing is a way to manage the actual tokens stored in the Keychain from the GUI.

**Tasks:**
- Add a "Manage Credentials" section or sheet (accessible from SettingsView) where users can:
  - Create a new credential account (name + GitHub token + Anthropic key)
  - Edit an existing credential account's tokens (using `SecureField` for token entry)
  - Delete a credential account
- Tokens are saved to Keychain via `SettingsService` credential methods, only the account name is saved in the repo config
- List existing credential accounts (from `SettingsService.listCredentialAccounts()`) so users can pick from known accounts or create new ones
- Show masked token status (e.g., "GitHub token: stored" / "not set") for each account — do NOT display raw tokens

## - [x] Phase 5: Add CLI Commands for Credential Management

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Thin command layer — each subcommand orchestrates via SettingsService/use cases; CredentialsCommand nested under ConfigCommand following existing subcommand pattern; validation at command boundary (account existence checks, empty token guards)

**Skills to read**: `swift-app-architecture:swift-architecture`, `python-architecture:cli-architecture`

Add a `credentials` subcommand group under `config` for managing credential accounts from the terminal. Note: `config add` already accepts `--github-account <name>`, and `GitHubServiceFactory`'s error message already references `config credentials add`.

**CLI Architecture Notes:**
- **Thin command layer**: Each subcommand's `run()` should only orchestrate — instantiate `SettingsService`, call the appropriate credential method, format output, and handle errors. No business logic in the command itself.
- **Explicit parameters**: Commands receive all inputs via ArgumentParser `@Argument`/`@Option` properties — never read environment variables directly in a command's `run()`.
- **Consistent structure**: Follow the existing `ConfigCommand` subcommand pattern — each credential subcommand is a nested `AsyncParsableCommand` struct inside `CredentialsCommand`, using `SettingsService` methods the same way `AddCommand`/`RemoveCommand`/`ListCommand` do today.
- **Error handling at command boundary**: Credential commands are a system boundary (user input). Validate account names are non-empty, handle Keychain errors (e.g., item not found), and print user-friendly messages to stderr via `printError()` before throwing `ValidationError`.

**Tasks:**
- Add `CredentialsCommand` as a new subcommand of `ConfigCommand` with these subcommands:
  - `config credentials add <account>` — prompts for (or reads from stdin) GitHub token and Anthropic key, saves to Keychain via `SettingsService`
  - `config credentials list` — lists all credential accounts from `SettingsService.listCredentialAccounts()`
  - `config credentials remove <account>` — removes a credential account via `SettingsService.removeCredentials(account:)`
  - `config credentials show <account>` — shows masked tokens (e.g., `ghp_...abc`) for verification
- Commands should confirm success/failure to stdout
- Accept tokens via stdin (for piping) to avoid tokens appearing in shell history: `echo "ghp_xxx" | swift run PRRadarMacCLI config credentials add work --github-token-stdin`

## - [x] Phase 6: Validation

**Skills used**: `swift-testing`
**Principles applied**: All automated checks pass — `swift build` (no warnings), `swift test` (481 tests in 53 suites), `swift build -c release` (success)

**Skills to read**: `swift-testing`

**Automated:**
- Run `swift build` — project compiles without warnings
- Run `swift test` — all existing tests pass, new tests pass
- Run `swift build -c release` — release build succeeds

**Manual verification:**
- `swift run PRRadarMacCLI config credentials add work` — saves tokens to Keychain
- `swift run PRRadarMacCLI config credentials list` — shows stored accounts
- `swift run PRRadarMacCLI config add my-repo --repo-path /path --github-account work` — creates config referencing account
- `swift run PRRadarMacCLI diff 1 --config my-repo` — resolves token from Keychain via github account
- Verify env var override still works: `GITHUB_TOKEN=xxx swift run PRRadarMacCLI diff 1 --config my-repo`
- Verify `.env` file still works
- Open MacApp, confirm credential management UI can add/view/remove credential accounts
- Confirm repo config editor shows `githubAccount` field and links to stored credentials
