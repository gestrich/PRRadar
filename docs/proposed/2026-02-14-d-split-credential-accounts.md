# Credential Resolution Cleanup & Split by Provider

Addresses all remaining TODOs from commit `f159721` (Phase 3: Keychain integration). Rewrites `CredentialResolver` with a clean layered architecture, fixes layer violations in the App layer, and separates GitHub/Anthropic credential resolution.

Preliminary work already completed: string constant extraction (`githubTokenKey`, `anthropicAPIKeyKey`, `defaultCredentialAccount`) and documentation of the "default" account convention.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | Layer responsibilities and dependency rules |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns for SettingsView changes |
| `swift-testing` | Test style guide |

## Background

After Phase 3 (Keychain integration), credential resolution is tangled:

1. `CredentialResolver.init` defaults to calling `PRRadarEnvironment.build()` to get its environment
2. `PRRadarEnvironment.build()` calls `loadKeychainSecrets()`, which injects Keychain values into the env dict
3. By the time `CredentialResolver.resolveGitHubToken()` runs, the token is already in the environment — the Keychain fallback inside `CredentialResolver` is dead code

Additionally, `credentialAccount` is a single string used for both GitHub and Anthropic Keychain lookups. GitHub tokens are per-repo/per-identity, but Anthropic API keys are global — coupling them forces users to duplicate their Anthropic key under every account name.

There are also two layer violations: `PRModel.isStale()` directly calls `GitHubServiceFactory` instead of going through a use case, and `PostSingleCommentUseCase` takes loose parameters instead of a config.

### Desired architecture

Two top-level methods — `getGitHubToken()` and `getAnthropicKey()` — that each do the full resolution chain (process env → .env → Keychain). Each method **knows** the domain-specific details (env var key, keychain type, which account to use) but **delegates** actual lookups to generic lower-level services that know nothing about GitHub or Anthropic:

```
getGitHubToken()                         getAnthropicKey()
  │ knows: envKey="GITHUB_TOKEN"           │ knows: envKey="ANTHROPIC_API_KEY"
  │ knows: keychainType="github-token"     │ knows: keychainType="anthropic-api-key"
  │ knows: account=githubAccount           │ knows: account=always "default"
  │                                        │
  ├─→ processEnvironment[envKey]           ├─→ processEnvironment[envKey]
  ├─→ dotEnv[envKey]                       ├─→ dotEnv[envKey]
  └─→ keychain.load(account, type)         └─→ keychain.load("default", type)
        ↑                                        ↑
        generic: no GitHub/Anthropic knowledge
```

The lower-level services:
- **Process environment** — `[String: String]` from `ProcessInfo.processInfo.environment`
- **DotEnv** — `[String: String]` loaded from `.env` file (extracted from `PRRadarEnvironment`)
- **Keychain** — generic `loadCredential(account:type:)` on `SettingsService`

### Files involved

- `PRRadarConfigService/SettingsService.swift` — add generic `loadCredential(account:type:)`
- `PRRadarConfigService/CredentialResolver.swift` — rewrite with layered architecture
- `PRRadarConfigService/PRRadarEnvironment.swift` — extract `loadDotEnv`, delegate credential loading
- `PRRadarConfigService/RepoConfiguration.swift` — rename `credentialAccount` → `githubAccount`
- `PRRadarConfigService/PRRadarConfig.swift` — rename `credentialAccount` → `githubAccount`
- `PRRadarCLIService/GitHubServiceFactory.swift` — update to use new resolver
- `PRRadarCLIService/ClaudeAgentClient.swift` — rename, remove TODO
- `PRReviewFeature/usecases/PostSingleCommentUseCase.swift` — refactor to accept config
- `MacApp/Models/PRModel.swift` — extract `CheckPRStalenessUseCase`
- `MacCLI/Commands/ConfigCommand.swift` — rename CLI flag
- `MacApp/UI/SettingsView.swift` — rename label
- Feature layer use cases — update `credentialAccount` references

## - [x] Phase 1: Resolve credentials upstream of `ClaudeAgentClient`

**Principles applied**: Services receive resolved credentials, not resolution mechanisms; non-optional types enforce required dependencies at compile time

The TODO at `ClaudeAgentClient.swift:158-163` says credentials should be resolved upstream. Fix the design: `ClaudeAgentClient` should not know about credential resolution, and it should not be possible to create one without valid credentials.

- Create `ClaudeAgentEnvironment` struct with a non-optional `anthropicAPIKey: String` and an internal `subprocessEnvironment: [String: String]`. Includes `init(resolvedEnvironment:)` that throws `missingAPIKey` if the key isn't present, and `static func build(credentialAccount:)` that wraps `PRRadarEnvironment.build()`.
- Add `ClaudeAgentError.missingAPIKey` for early failure when the key isn't found.
- Make `PRRadarEnvironment.anthropicAPIKeyKey` and `githubTokenKey` public so they can be referenced by constant.
- Replace `credentialAccount: String?` with `environment: ClaudeAgentEnvironment` on `ClaudeAgentClient`.
- Update callers (`PrepareUseCase`, `AnalyzeUseCase`, `SelectiveAnalyzeUseCase`) to use `ClaudeAgentEnvironment.build(credentialAccount:)`.

## - [x] Phase 2: Add generic `loadCredential` to `SettingsService`

**Principles applied**: Generic method for reuse by CredentialResolver; domain-specific methods delegate to it

`SettingsService` currently has domain-specific methods (`loadGitHubToken`, `loadAnthropicKey`) that hard-code the keychain type strings. Add a generic public method so callers can specify both account and type. The domain-specific methods become convenience wrappers.

```swift
// New generic method
public func loadCredential(account: String, type: String) throws -> String {
    try keychain.string(forKey: credentialKey(account: account, type: type))
}

// Existing methods delegate to it
public func loadGitHubToken(account: String) throws -> String {
    try loadCredential(account: account, type: Self.gitHubTokenType)
}

public func loadAnthropicKey(account: String) throws -> String {
    try loadCredential(account: account, type: Self.anthropicKeyType)
}
```

Keep the domain-specific methods — they're used by credential management CLI commands (`config credentials add/remove/list`). The generic method is for `CredentialResolver`.

## - [x] Phase 3: Extract `loadDotEnv` as a reusable function

**Principles applied**: Pure function returns values instead of mutating inout; public for reuse by CredentialResolver

Currently, `PRRadarEnvironment.loadDotEnv(into:)` mutates a dict in-place and is private. Extract it into a standalone static method that returns a `[String: String]` so `CredentialResolver` can check `.env` values independently of `PRRadarEnvironment.build()`.

```swift
// PRRadarEnvironment.swift
public static func loadDotEnv() -> [String: String] {
    var values: [String: String] = [:]
    // ... same directory-walking logic, but populates `values` instead of mutating env ...
    return values
}
```

Update `build()` to call this new method and merge the result into env. The old `private static func loadDotEnv(into:)` is replaced.

## - [x] Phase 4a: Refactor `PostSingleCommentUseCase` to accept config

**Principles applied**: Use cases receive config at init, not as loose parameters; consistent with all other use cases in the Features layer

`PostSingleCommentUseCase.execute()` takes `repoPath` and `credentialAccount` as loose parameters instead of receiving a `RepositoryConfiguration` like every other use case.

Before:
```swift
public struct PostSingleCommentUseCase: Sendable {
    public init() {}

    public func execute(
        comment: PRComment, commitSHA: String, prNumber: String,
        repoPath: String, credentialAccount: String? = nil
    ) async throws -> Bool {
        let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: repoPath, credentialAccount: credentialAccount)
        // ...
    }
}
```

After:
```swift
public struct PostSingleCommentUseCase: Sendable {
    let config: RepositoryConfiguration
    public init(config: RepositoryConfiguration) { self.config = config }

    public func execute(comment: PRComment, commitSHA: String, prNumber: String) async throws -> Bool {
        let (gitHub, _) = try await GitHubServiceFactory.create(
            repoPath: config.repoPath,
            credentialAccount: config.credentialAccount
        )
        // ...
    }
}
```

Update the caller in `PRModel` to pass `config`.

## - [x] Phase 4b: Move staleness check into `SyncPRUseCase`

**Principles applied**: Staleness decision belongs in the use case that owns syncing, not in the App-layer model; reused `PhaseOutputParser` pattern from `LoadPRDetailUseCase` for reading cached metadata

`PRModel.isStale()` directly creates a `GitHubServiceFactory` and calls `gitHub.getPRUpdatedAt()`. Per the architecture, App-layer models should not know about service-layer factories. Rather than creating a thin `CheckPRStalenessUseCase`, fold the staleness check into `SyncPRUseCase` where the sync decision naturally lives.

### Changes to `SyncPRUseCase`

Add a `force` parameter to `execute()`. When `force: false`, read the cached `gh-pr.json` to get the stored `updatedAt`, compare it against GitHub's current value, and skip the full acquisition if unchanged:

```swift
public func execute(prNumber: String, force: Bool = false) -> AsyncThrowingStream<PhaseProgress<SyncSnapshot>, Error> {
    AsyncThrowingStream { continuation in
        continuation.yield(.running(phase: .diff))
        Task {
            do {
                let (gitHub, gitOps) = try await GitHubServiceFactory.create(
                    repoPath: config.repoPath,
                    credentialAccount: config.credentialAccount
                )

                guard let prNum = Int(prNumber) else { ... }

                // Staleness check: if not forced, compare cached updatedAt with GitHub
                if !force {
                    let cachedUpdatedAt = Self.readCachedUpdatedAt(config: config, prNumber: prNumber)
                    if let cachedUpdatedAt {
                        let currentUpdatedAt = try await gitHub.getPRUpdatedAt(number: prNum)
                        if cachedUpdatedAt == currentUpdatedAt {
                            let snapshot = Self.parseOutput(config: config, prNumber: prNumber)
                            continuation.yield(.completed(output: snapshot))
                            continuation.finish()
                            return
                        }
                    }
                }

                // Stale or forced — do the full acquisition
                // ... existing fetch logic ...
            }
        }
    }
}

/// Read updatedAt from the cached gh-pr.json metadata file.
private static func readCachedUpdatedAt(config: RepositoryConfiguration, prNumber: String) -> String? {
    let metadataDir = DataPathsService.phaseDirectory(
        outputDir: config.absoluteOutputDir, prNumber: prNumber, phase: .metadata
    )
    let ghPRPath = "\(metadataDir)/gh-pr.json"
    guard let data = FileManager.default.contents(atPath: ghPRPath),
          let pr = try? JSONDecoder().decode(GitHubPullRequest.self, from: data) else {
        return nil
    }
    return pr.updatedAt
}
```

### Changes to `PRModel`

- Remove `isStale()` entirely (including the TODO comment)
- Simplify `refreshDiff(force:)` to always call `SyncPRUseCase.execute(prNumber:force:)` — the use case decides whether to fetch
- The `hasCachedData` / `shouldFetch` logic collapses: if there's no cache, the use case won't find a `gh-pr.json` and will proceed with the full fetch; if there is cache and it's fresh, the use case returns immediately

```swift
func refreshDiff(force: Bool = false) async {
    refreshTask?.cancel()

    let hasCachedData = syncSnapshot != nil
    if hasCachedData {
        phaseStates[.diff] = .refreshing(logs: "Checking PR #\(prNumber)...\n")
    } else {
        phaseStates[.diff] = .running(logs: "Fetching diff for PR #\(prNumber)...\n")
    }

    let useCase = SyncPRUseCase(config: config)
    // ... call useCase.execute(prNumber: prNumber, force: force) ...
}
```

## - [x] Phase 5: Rewrite `CredentialResolver` with layered architecture

**Principles applied**: Explicit dependencies (processEnvironment, dotEnv) eliminate circular call to `PRRadarEnvironment.build()`; Anthropic always uses "default" account while GitHub uses configured account; ordered resolution chain: process env → .env → keychain

Replace the current `CredentialResolver` with one that takes explicit lookup sources as dependencies and has `getGitHubToken()` / `getAnthropicKey()` methods that orchestrate the full resolution chain.

```swift
public struct CredentialResolver: Sendable {
    private let processEnvironment: [String: String]
    private let dotEnv: [String: String]
    private let settingsService: SettingsService
    private let credentialAccount: String?

    public init(
        settingsService: SettingsService,
        credentialAccount: String? = nil,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnv: [String: String]? = nil
    ) {
        self.settingsService = settingsService
        self.credentialAccount = credentialAccount
        self.processEnvironment = processEnvironment
        self.dotEnv = dotEnv ?? PRRadarEnvironment.loadDotEnv()
    }

    public func getGitHubToken() -> String? {
        let envKey = PRRadarEnvironment.githubTokenKey
        let keychainType = "github-token"
        let account = (credentialAccount?.isEmpty ?? true)
            ? PRRadarEnvironment.defaultCredentialAccount
            : credentialAccount!

        if let v = processEnvironment[envKey] { return v }
        if let v = dotEnv[envKey] { return v }
        return try? settingsService.loadCredential(account: account, type: keychainType)
    }

    public func getAnthropicKey() -> String? {
        let envKey = PRRadarEnvironment.anthropicAPIKeyKey
        let keychainType = "anthropic-api-key"

        if let v = processEnvironment[envKey] { return v }
        if let v = dotEnv[envKey] { return v }
        return try? settingsService.loadCredential(
            account: PRRadarEnvironment.defaultCredentialAccount,
            type: keychainType
        )
    }
}
```

Key properties:
- No circular dependency — never calls `PRRadarEnvironment.build()`
- Each method knows the domain specifics (env var key, keychain type, account rules)
- All lookups delegate to generic services (dict lookup, `loadCredential`)
- Anthropic always uses `"default"` account; GitHub uses the configured account
- Explicit, ordered resolution: process env → .env → keychain

Update `GitHubServiceFactory` to use `getGitHubToken()` (was `resolveGitHubToken()`).

## - [x] Phase 6: Update `PRRadarEnvironment.build()` to use `CredentialResolver`

**Principles applied**: Subprocess env construction belongs in `ClaudeAgentEnvironment` (its only consumer); credential constants belong on `CredentialResolver` (the credential authority); pure `.env` loading extracted to `EnvironmentSDK` (SDK layer, Foundation-only)

Removed `PRRadarEnvironment` entirely:
- `build()` and `loadKeychainSecrets` merged into `ClaudeAgentEnvironment.build()` using `CredentialResolver`
- `githubTokenKey`, `anthropicAPIKeyKey`, `defaultCredentialAccount` moved to `CredentialResolver`
- `loadDotEnv()` moved to new `EnvironmentSDK` target as `DotEnvironmentLoader`

## - [x] Phase 7: Rename `credentialAccount` to `githubAccount`

Rename the field across the codebase to clarify its purpose. This is a pure rename with no behavior change.

- `RepositoryConfigurationJSON.credentialAccount` → `githubAccount`
- `RepositoryConfiguration.credentialAccount` → `githubAccount`
- `CredentialResolver.credentialAccount` → `githubAccount`
- `ClaudeAgentClient.credentialAccount` → `githubAccount`
- `GitHubServiceFactory.create(credentialAccount:)` → `create(githubAccount:)`
- `PRRadarEnvironment.build(credentialAccount:)` → `build(githubAccount:)`
- All callers that pass `credentialAccount:` → `githubAccount:`
- `ConfigCommand.AddCommand.credentialAccount` → `githubAccount`

Keep JSON backwards compatibility: add a `CodingKeys` enum to `RepositoryConfigurationJSON` that maps `githubAccount` to the `"credentialAccount"` JSON key, so existing settings files still load. (Or just rename the JSON key and accept the one-time migration — Bill's call.)

## - [x] Phase 8: Update UI and CLI labels

**Principles applied**: Labels now reflect the actual purpose (GitHub-specific account selection); help text clarifies the token lookup scope

- `SettingsView`: Rename "Credential Account" label to "GitHub Account". Update help text to explain this only affects GitHub token lookup.
- `ConfigCommand.AddCommand`: Rename `--credential-account` to `--github-account`. Keep `--credential-account` as a hidden alias for backwards compatibility (or not — Bill's call).
- `presentableDescription`: Change `"credentials:"` to `"github account:"`.

## - [x] Phase 9: Add tests

**Skills used**: `swift-testing`
**Principles applied**: Arrange-Act-Assert pattern; all dependencies injected directly (no mocking needed); tests verify resolution order and account selection behavior

Add tests to verify the layered resolution behavior:

1. `getGitHubToken` checks process env first, then .env, then keychain
2. `getAnthropicKey` checks process env first, then .env, then keychain
3. `getGitHubToken` uses the configured account for keychain lookup
4. `getAnthropicKey` always uses `"default"` account regardless of configured account
5. A user with GitHub token under "work" and Anthropic key under "default" can resolve both
6. Earlier sources take precedence (process env > .env > keychain)

Each source is an explicit dependency, so tests inject controlled values — no mocking needed.

## - [ ] Phase 10: Validation

**Skills to read**: `swift-testing`

- `swift build` — no compile errors
- `swift test` — all tests pass (existing + new)
- Manual spot check: `swift run PRRadarMacCLI diff 1 --config test-repo` to verify credential resolution still works end-to-end
