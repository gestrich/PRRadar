# Phase 3 TODO Cleanup Plan

Addresses the TODOs left in commit `f159721` (Phase 3: Integrate Keychain into token resolution). The TODOs fall into four groups — two are real problems worth fixing, one is a design question that needs a decision, and one is fine as-is.

---

## Group 1: The Two Config Types (Fix)

**TODOs:**
- `PRRadarConfig.swift:3` — "The name of this config file is confusing. I think more accurately this is a RepositoryConfiguration"
- `AppModel.swift:29` — "More confusion on the relationship between RepoConfiguration and PRRadarConfig. It seems like we should just have one config type that is used everywhere."

**What's actually happening:**

`RepoConfiguration` is the **persisted** model — what gets saved to `settings.json`. It has settings-specific fields (`id`, `name`, `isDefault`, `rulesDir`).

`PRRadarConfig` is the **runtime** model — the resolved values the pipeline needs to do its work. It has runtime-specific fields (`agentScriptPath`, `resolvedOutputDir`, `absoluteOutputDir`, `prDataDirectory(for:)`).

The confusion is real, but merging them is the wrong fix. They serve different purposes:

| | `RepoConfiguration` | `PRRadarConfig` |
|---|---|---|
| Layer | ConfigService (persisted) | ConfigService (runtime) |
| Codable | Yes (JSON) | No |
| Contains `id`, `name`, `isDefault` | Yes | No |
| Contains `agentScriptPath` | No | Yes |
| Contains `rulesDir` | Yes | No |
| Has path resolution logic | No | Yes |

The problem isn't that there are two types — it's that `PRRadarConfig`'s name doesn't communicate what it is. `RepoConfiguration` is the *user's saved config*. `PRRadarConfig` is the *resolved runtime context for pipeline execution*.

**Recommendation: Rename, don't merge.**

Rename `PRRadarConfig` → `PipelineContext` (or `PRRadarPipelineConfig`). This makes the distinction obvious:
- `RepoConfiguration` = what the user configured and saved
- `PipelineContext` = what the pipeline needs at runtime, derived from a `RepoConfiguration`

A factory method would make the relationship explicit:

```swift
extension PipelineContext {
    static func from(_ repoConfig: RepoConfiguration, agentScriptPath: String) -> PipelineContext
}
```

This also eliminates the manual field-copying in `AppModel.selectConfig()` and `resolveConfig()` in the CLI — both currently cherry-pick fields from `RepoConfiguration` into `PRRadarConfig`.

**Effort:** Small. Rename + add factory method. No behavioral change.

---

## Group 2: Credential Resolution Duplication (Fix)

**TODOs:**
- `CredentialResolver.swift:15` — "We are also doing environment things with these same strings in PRRadarEnvironment. This seems sketchy"
- `PRRadarEnvironment.swift:27-30` — "This needs research... There is not link between anthropic and Github. They are separate credentials that just happen to be loaded together here."
- `ClaudeAgentClient.swift:158` — "It seems the credentials should have been resolved upstream before getting here."
- `PRRadarEnvironment.swift:31` — "These ANTHROPIC_API_KEY should be static let"

**What's actually happening:**

There are two independent credential resolution paths:

1. **`CredentialResolver`** — used by `GitHubServiceFactory` to get a GitHub token as a Swift `String`. Clean, straightforward: env var → Keychain → nil.

2. **`PRRadarEnvironment.loadKeychainSecrets()`** — used by `ClaudeAgentClient` to build an env dict for the Python subprocess. Injects Keychain values into the environment so the Python script can read `ANTHROPIC_API_KEY` and `GITHUB_TOKEN`.

The duplication exists because these serve fundamentally different consumers:
- Swift code needs a **resolved token value** (`CredentialResolver`)
- The Python subprocess needs an **environment dictionary** with the right keys set (`PRRadarEnvironment`)

**The TODO about ClaudeAgentClient is correct in spirit.** The `ClaudeAgentClient` shouldn't know about `credentialAccount` — it should receive an already-built environment dictionary. But the current design works because `ClaudeAgentClient` needs to *build the full process environment* (PATH, HOME, .env vars, Keychain secrets), and `PRRadarEnvironment.build()` is the one place that assembles all of that.

**Recommendation: Consolidate, don't eliminate.**

Make `CredentialResolver` the single source of truth for credential logic, and have `PRRadarEnvironment` delegate to it:

```swift
// PRRadarEnvironment.swift
private static func loadKeychainSecrets(into env: inout [String: String], credentialAccount: String?) {
    let resolver = CredentialResolver(
        settingsService: SettingsService(),
        credentialAccount: credentialAccount,
        environment: env  // pass current env so resolver checks it
    )
    if env[Keys.anthropicAPIKey] == nil, let key = resolver.resolveAnthropicKey() {
        env[Keys.anthropicAPIKey] = key
    }
    if env[Keys.githubToken] == nil, let token = resolver.resolveGitHubToken() {
        env[Keys.githubToken] = token
    }
}
```

Wait — this has a subtlety. `CredentialResolver.resolveGitHubToken()` already checks the environment and then falls back to Keychain. If you pass the current `env` dict and the env var isn't set, it'll check Keychain — which is exactly what `loadKeychainSecrets` does manually today. So the resolver already encapsulates the full priority chain.

The real consolidation: `loadKeychainSecrets` can just use `CredentialResolver` and write the resolved values back into `env`. The resolver's logic stays, the duplication goes away.

**For ClaudeAgentClient:** Keep `credentialAccount` on it. The alternative (resolving credentials upstream and passing a pre-built environment) would mean the caller needs to know about `PRRadarEnvironment`, PATH setup, .env loading, etc. That's worse. The current design is actually the right tradeoff — `ClaudeAgentClient` doesn't know about Keychain or env vars, it just passes `credentialAccount` to `PRRadarEnvironment.build()` which handles everything. **Challenge: this TODO is aspirational but the current approach is the pragmatic choice. Leave `ClaudeAgentClient` as-is.**

**For string constants:** Yes, extract `"GITHUB_TOKEN"` and `"ANTHROPIC_API_KEY"` to static lets. Minor but prevents typo bugs across `CredentialResolver` and `PRRadarEnvironment`.

**Effort:** Small. Delegate from `PRRadarEnvironment` to `CredentialResolver`, extract string constants.

---

## Group 3: The "default" Account Fallback (Decide)

**TODOs:**
- `CredentialResolver.swift:35` — "Need to research if an empty credentialAccount is normal. Fallbacks like 'default' are unclear why they exist."

**What's actually happening:**

When `credentialAccount` is `nil` (no account configured for a repo), the code falls back to `"default"` as the Keychain lookup key. This means `default/github-token` and `default/anthropic-api-key` in the Keychain.

This fallback exists because of the spec design (from Phase 1): *"A nil or empty account name uses 'default' as the account name."* The rationale: users who only have one set of credentials shouldn't need to think about account names. They run `config credentials add` (no account name), their tokens go under `"default"`, and repo configs with no `credentialAccount` find them automatically.

**This is the correct behavior.** The alternative — requiring every repo config to explicitly name a credential account — adds friction for the common case (one GitHub account, one Anthropic key). The `"default"` fallback is the "convention over configuration" approach.

**What's actually confusing** is that the `"default"` string appears as a magic literal in two places (`CredentialResolver.loadFromKeychain` and `PRRadarEnvironment.loadKeychainSecrets`). It should be a shared constant.

**Recommendation: Keep the behavior, extract the constant, remove the TODO.**

```swift
// In SettingsService or a shared location:
public static let defaultCredentialAccount = "default"
```

Replace the inline `"default"` in both `CredentialResolver` and `PRRadarEnvironment`. The nil-coalescing logic is fine:

```swift
let account = credentialAccount?.nonEmpty ?? Self.defaultCredentialAccount
```

(Add a `String.nonEmpty` helper or just keep the existing check.)

**Effort:** Trivial. One constant, two call sites.

---

## Group 4: Layer Violations in MacApp (Fix)

**TODOs:**
- `PRModel.swift:275` — "This is sketchy that we are creating the service here... PRModel should be using a use case for this"
- `PostSingleCommentUseCase.swift:8` — "Like our other use cases, this should be passed the config"

**What's actually happening:**

`PRModel.isStale()` directly creates a `GitHubServiceFactory` and calls `gitHub.getPRUpdatedAt()`. The model is reaching into the service layer to make an API call. Per the architecture, App-layer models should work through Feature-layer use cases.

`PostSingleCommentUseCase.execute()` takes `repoPath` and `credentialAccount` as loose parameters instead of receiving a `PRRadarConfig` like every other use case.

**Both TODOs are correct — these are real layer violations / inconsistencies.**

However, the `PRModel.isStale()` one is a pre-existing issue that Phase 3 didn't introduce — it just made it more visible by adding `credentialAccount` to the factory call. Worth fixing, but not a Phase 3 regression.

**Recommendation: Fix both.**

For `PostSingleCommentUseCase`: Accept `PRRadarConfig` like other use cases:
```swift
public struct PostSingleCommentUseCase: Sendable {
    let config: PRRadarConfig
    public init(config: PRRadarConfig) { self.config = config }

    public func execute(comment:commitSHA:prNumber:) async throws -> Bool {
        let (gitHub, _) = try await GitHubServiceFactory.create(
            repoPath: config.repoPath,
            credentialAccount: config.credentialAccount
        )
        // ...
    }
}
```

For `PRModel.isStale()`: Create a small use case (or add to an existing one):
```swift
public struct CheckPRStalenessUseCase: Sendable {
    let config: PRRadarConfig
    public func execute(prNumber: Int, lastUpdatedAt: String) async throws -> Bool {
        let (gitHub, _) = try await GitHubServiceFactory.create(
            repoPath: config.repoPath,
            credentialAccount: config.credentialAccount
        )
        let currentUpdatedAt = try await gitHub.getPRUpdatedAt(number: prNumber)
        return lastUpdatedAt != currentUpdatedAt
    }
}
```

Then `PRModel.isStale()` becomes:
```swift
private func isStale() async -> Bool {
    guard let storedUpdatedAt = metadata.updatedAt else { return true }
    let useCase = CheckPRStalenessUseCase(config: config)
    return (try? await useCase.execute(prNumber: metadata.number, lastUpdatedAt: storedUpdatedAt)) ?? true
}
```

**Effort:** Small. Two use case changes, two call site updates.

---

## Summary

| Group | Problem | Action | Effort |
|---|---|---|---|
| 1. Config types | Names confusing, not the types themselves | Rename `PRRadarConfig` → `PipelineContext`, add factory | Small |
| 2. Credential duplication | Two places resolving credentials | Have `PRRadarEnvironment` delegate to `CredentialResolver`; extract string constants; keep `ClaudeAgentClient` as-is | Small |
| 3. "default" account | Magic string, unclear intent | Extract constant, keep behavior | Trivial |
| 4. Layer violations | PRModel calls factory directly; PostSingleCommentUseCase inconsistent | Add `CheckPRStalenessUseCase`; refactor PostSingleComment to take config | Small |

All four are independently shippable. Groups 2 and 3 are closely related (both touch `CredentialResolver` + `PRRadarEnvironment`) and should be done together.

### Suggested order:
1. Group 3 (trivial constant extraction, unblocks group 2)
2. Group 2 (consolidate credential resolution)
3. Group 4 (use case fixes)
4. Group 1 (rename — touches the most files but is mechanical)
