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

## - [ ] Phase 2: Add Credential Account to RepoConfiguration

**Skills to read**: `swift-app-architecture:swift-architecture`

Update `RepoConfiguration` to reference a credential account name instead of storing a raw GitHub token.

**Tasks:**
- Add `credentialAccount: String?` property to `RepoConfiguration`
- Remove `githubToken: String?` property from `RepoConfiguration`
- Remove `githubToken` from `PRRadarConfig`
- Handle `Codable` backwards compatibility — old JSON files with `githubToken` should still decode without error (the field is already `String?`)
- Add a migration path: on first load, if a config has a `githubToken` but no `credentialAccount`, migrate the token to Keychain under a default account named after the config, set `credentialAccount` to that name, and save
- Update `presentableDescription` to show the credential account name (if set)
- Remove the `--github-token` CLI flag from `CLIOptions` and `RunAllCommand`
- Update all ~15 call sites that pass `config.githubToken` through the system

## - [ ] Phase 3: Integrate Keychain into Token Resolution

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

## - [ ] Phase 4: Integrate Keychain into MacApp GUI

**Skills to read**: `swift-app-architecture:swift-swiftui`

Update the MacApp settings UI to manage credential accounts.

**Tasks:**
- Replace the GitHub token `SecureField` in `SettingsView.swift` with a credential account picker/text field
- Add a "Manage Credentials" section or sheet where users can:
  - Create a new credential account (name + GitHub token + Anthropic key)
  - Edit an existing credential account's tokens
  - Delete a credential account
- Tokens are saved to Keychain via `KeychainService`, only the account name is saved in the repo config
- In `AppModel` / `PRModel`, update token resolution to use `CredentialResolver` with the config's credential account
- Show which credential account each repo config uses in the settings list

## - [ ] Phase 5: Add CLI Commands for Credential Management

**Skills to read**: `swift-app-architecture:swift-architecture`

Add subcommands under `config` for managing credential accounts from the terminal.

**Tasks:**
- `config credentials add <account>` — prompts for (or reads from stdin) GitHub token and Anthropic key, saves to Keychain
- `config credentials list` — lists all credential accounts stored in Keychain
- `config credentials remove <account>` — removes a credential account from Keychain
- `config credentials show <account>` — shows masked tokens (e.g., `ghp_...abc`) for verification
- Commands should confirm success/failure to stdout
- Accept tokens via stdin (for piping) to avoid tokens appearing in shell history: `echo "ghp_xxx" | swift run PRRadarMacCLI config credentials add work --github-token-stdin`
- Update `config add` to accept `--credential-account <name>` instead of `--github-token`

## - [ ] Phase 6: Validation

**Skills to read**: `swift-testing`

**Automated:**
- Run `swift build` — project compiles without warnings
- Run `swift test` — all existing tests pass, new tests pass
- Run `swift build -c release` — release build succeeds

**Manual verification:**
- `swift run PRRadarMacCLI config credentials add work` — saves tokens to Keychain
- `swift run PRRadarMacCLI config credentials list` — shows stored accounts
- `swift run PRRadarMacCLI config add my-repo --repo-path /path --credential-account work` — creates config referencing account
- `swift run PRRadarMacCLI diff 1 --config my-repo` — resolves token from Keychain via credential account
- Verify env var override still works: `GITHUB_TOKEN=xxx swift run PRRadarMacCLI diff 1 --config my-repo`
- Verify `.env` file still works
- Open MacApp, confirm settings UI manages credential accounts and repos reference them
- Verify old `settings.json` with `githubToken` field migrates to Keychain on load
- Verify `settings.json` no longer contains raw tokens after migration
