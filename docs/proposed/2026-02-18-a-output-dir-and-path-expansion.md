## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer placement, dependency flow |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, enum-based state, observable model conventions |
| `swift-testing` | Test style guide and conventions |

## Background

Two path handling improvements:

1. **Output directory** is currently per-repo config (`RepositoryConfigurationJSON.outputDir`). It defaults to `"code-reviews"` (relative to repo root) when empty. Bill wants it promoted to an app-level setting — a single absolute path (with tilde expansion) shared across all repos. This eliminates the confusing relative-path resolution and makes it a first-class global preference. The existing per-command `--output-dir` CLI override stays for one-off use.

2. **Rules directory** already lives correctly in per-repo config. It just needs tilde expansion support, matching what `absoluteOutputDir` already does for `outputDir`.

Current `absoluteOutputDir` logic (the model for both changes):
```swift
public var absoluteOutputDir: String {
    let expanded = NSString(string: resolvedOutputDir).expandingTildeInPath
    if NSString(string: expanded).isAbsolutePath {
        return expanded
    }
    return "\(repoPath)/\(expanded)"
}
```

### Scope of outputDir migration

`outputDir` is consumed exclusively through `config.absoluteOutputDir` and `config.prDataDirectory(for:)`. Those computed properties are on `RepositoryConfiguration`, which is the runtime config. Since we're moving the value from per-repo JSON to app-level settings, the runtime `RepositoryConfiguration` will read the global value instead. All downstream consumers (`DataPathsService`, use cases, CLI commands) already go through these computed properties, so they won't need changes.

## Phases

## - [x] Phase 1: Extract path resolution into a reusable SDK utility

**Skills to read**: `swift-app-architecture:swift-architecture`

The tilde expansion + relative-to-base resolution pattern is duplicated in `PRRadarConfig.absoluteOutputDir` and `PRDiscoveryService`. Extract it into a new `PathUtilities` enum (or extend `String`) in `EnvironmentSDK` (the existing SDK for environment/config concerns):

```swift
public enum PathUtilities {
    /// Expands `~`, then resolves relative paths against `basePath`.
    /// Absolute paths pass through with only tilde expansion.
    public static func resolve(_ path: String, relativeTo basePath: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        if NSString(string: expanded).isAbsolutePath {
            return expanded
        }
        return "\(basePath)/\(expanded)"
    }
}
```

This supports three cases:
- `code-review-rules` → `{basePath}/code-review-rules` (relative)
- `~/shared-rules` → `/Users/bill/shared-rules` (tilde expansion)
- `/opt/company-rules` → `/opt/company-rules` (absolute, unchanged)

Refactor `absoluteOutputDir` and `PRDiscoveryService` to call `PathUtilities.resolve(_:relativeTo:)`.

**Files**:
- `EnvironmentSDK/PathUtilities.swift` — new file with the utility
- `PRRadarConfig.swift` — refactor `absoluteOutputDir` to use `PathUtilities.resolve`
- `PRDiscoveryService.swift` — refactor to use `PathUtilities.resolve`

**Completed**: Added `PathUtilities` enum with both `resolve(_:relativeTo:)` and `expandTilde(_:)` methods. The `expandTilde` convenience was added because `PRDiscoveryService` only needs tilde expansion (no relative-to-base resolution). Added 7 unit tests. Added `EnvironmentSDK` to test target dependencies in Package.swift.

## - [x] Phase 2: Add tilde expansion for rulesDir

**Skills to read**: `swift-app-architecture:swift-architecture`

Add an `absoluteRulesDir` computed property to `RepositoryConfiguration` using the new utility:

```swift
public var absoluteRulesDir: String {
    PathUtilities.resolve(rulesDir, relativeTo: repoPath)
}
```

Update all consumers that currently pass `config.rulesDir` directly to file operations to use `config.absoluteRulesDir` instead:
- `PrepareCommand.swift` — CLI override still passes raw string, but config path goes through `absoluteRulesDir`
- `RunCommand.swift`, `RunAllCommand.swift` — same pattern
- `PRModel.swift` — Mac app caller
- `PrepareUseCase.swift` — receives resolved path from callers

Also update `defaultRulesDir` to return just the directory name (`"code-review-rules"`) rather than a full path, since `absoluteRulesDir` now handles resolution. Update `ConfigCommand.AddCommand` accordingly.

Update the UI placeholder in `SettingsView.swift` to hint at relative support: `"code-review-rules"`.

**Files**:
- `PRRadarConfig.swift` — add `absoluteRulesDir`, change `defaultRulesDir`
- `PrepareUseCase.swift` — use resolved path
- `PrepareCommand.swift`, `RunCommand.swift`, `RunAllCommand.swift` — update callers
- `PRModel.swift` — update caller
- `ConfigCommand.swift` — update default
- `SettingsView.swift` — update placeholder

**Completed**: Changed `defaultRulesDir` from `static func` (returning `"{repoPath}/code-review-rules"`) to `static var` (returning just `"code-review-rules"`). Added `absoluteRulesDir` computed property using `PathUtilities.resolve`. Updated all CLI commands and PRModel to use `absoluteRulesDir` as the fallback when no `--rules-dir` override is provided. `PrepareUseCase` itself didn't need changes since it receives the resolved path from callers. Updated SettingsView placeholder to `"code-review-rules"`.

## - [x] Phase 3: Add outputDir to AppSettings as a global setting

**Skills to read**: `swift-app-architecture:swift-architecture`

Add an `outputDir` field to `AppSettings`:

```swift
public struct AppSettings: Codable, Sendable {
    public var configurations: [RepositoryConfigurationJSON]
    public var outputDir: String  // New global setting
    ...
}
```

Default to `"code-reviews"`.

Remove `outputDir` from `RepositoryConfigurationJSON` and its init. Remove `outputDir` from `RepositoryConfiguration` along with the `resolvedOutputDir` computed property.

Move `absoluteOutputDir` and `prDataDirectory(for:)` to a new approach: since `absoluteOutputDir` needs `repoPath` for relative resolution, but the new design makes outputDir always absolute, the property simplifies to just tilde expansion (no relative-to-repo logic). It can live as a static method or be computed where needed. Evaluate whether `absoluteOutputDir` still belongs on `RepositoryConfiguration` or should move to a shared utility. The simplest path: keep it on `RepositoryConfiguration` but source the raw value from the app settings instead of per-repo JSON.

Actually, the cleanest approach: `RepositoryConfiguration.init(from:)` gains an `outputDir` parameter (sourced from `AppSettings.outputDir`). The `outputDirOverride` from CLI still works. `absoluteOutputDir` stays on `RepositoryConfiguration` since all consumers already use it there.

**Files**:
- `RepoConfiguration.swift` — add `outputDir` to `AppSettings`, remove from `RepositoryConfigurationJSON`
- `PRRadarConfig.swift` — update `RepositoryConfiguration.init(from:)` to accept outputDir parameter, simplify `absoluteOutputDir` (just tilde expand, require absolute)
- `SettingsService.swift` — no changes (just saves/loads AppSettings)

**Completed**: Added `outputDir` field to `AppSettings` with `defaultOutputDir = "code-reviews"` static constant. Added custom `init(from:)` decoder for backward compatibility with existing settings files that lack the `outputDir` key. Removed `outputDir` from `RepositoryConfigurationJSON` (including init, presentableDescription). Removed `resolvedOutputDir` from `RepositoryConfiguration` — the empty-string fallback is no longer needed since the value always comes from `AppSettings`. Updated `RepositoryConfiguration.init(from:)` to accept an `outputDir` parameter sourced from `AppSettings.outputDir`; the `outputDirOverride` from CLI still takes precedence. Updated all callers: `resolveConfig()` in CLI passes `settings.outputDir`, `AppModel.selectConfig()` passes `settingsModel.settings.outputDir`. Removed outputDir display from `ConfigurationDetailView` and edit field from `ConfigurationEditSheet`. Removed `--output-dir` from `ConfigCommand.AddCommand`. 486 tests pass.

## - [x] Phase 4: Update config resolution (CLI and MacApp) for global outputDir

**Skills to read**: `swift-app-architecture:swift-architecture`

CLI: Update `resolveConfig()` in `PRRadarMacCLI.swift` to load `AppSettings.outputDir` and pass it when constructing `RepositoryConfiguration`. The `--output-dir` CLI override still takes precedence.

Remove `--output-dir` from `ConfigCommand.AddCommand` (no longer per-repo).

MacApp: Update wherever `RepositoryConfiguration` is constructed to pass the global `outputDir`. This likely flows through `SettingsModel` which already has access to `AppSettings`.

Remove outputDir display from `ConfigurationDetailView` and the edit field from `ConfigurationEditSheet`.

**Files**:
- `PRRadarMacCLI.swift` — update `resolveConfig()` to pass `AppSettings.outputDir`
- `ConfigCommand.swift` — remove `--output-dir` from `AddCommand`
- `SettingsView.swift` — remove outputDir from detail view and edit sheet
- MacApp model files that construct `RepositoryConfiguration`

**Completed**: All Phase 4 work was already implemented during Phase 3. Verified: `resolveConfig()` in `PRRadarMacCLI.swift` passes `settings.outputDir` (line 93). `AppModel.selectConfig()` passes `settingsModel.settings.outputDir` (line 30). `ConfigCommand.AddCommand` has no `--output-dir` option. `ConfigurationDetailView` and `ConfigurationEditSheet` have no outputDir fields. Build passes.

## - [x] Phase 5: Add "General" settings tab for outputDir

**Skills to read**: `swift-app-architecture:swift-swiftui`

Add a third tab to `SettingsView`:

```swift
Tab("General", systemImage: "gearshape") {
    GeneralSettingsView()
}
```

`GeneralSettingsView` contains:
- Output directory path field (with Browse button, reusing `pathField` pattern)
- Save happens through `SettingsModel`

Add methods to `SettingsModel` for updating the global output dir (load/save through existing `SettingsService`).

**Files**:
- `SettingsView.swift` — add "General" tab, create `GeneralSettingsView`
- `SettingsModel.swift` — add `updateOutputDir(_:)` method

**Completed**: Added `GeneralSettingsView` as the first tab ("General" with gearshape icon) in `SettingsView`. The view uses a Form with an output directory text field and Browse button (NSOpenPanel for directory selection), plus a caption explaining tilde/relative path support. Saves on every keystroke via `onChange(of:)` calling `settingsModel.updateOutputDir(_:)`. Added `settingsService` as a direct dependency on `SettingsModel` (alongside existing use cases) so `updateOutputDir` can load/mutate/save without a dedicated use case. Updated test helper `makeModel()` to pass the new parameter. 486 tests pass.

## - [x] Phase 6: Add CLI commands for general settings

**Skills to read**: `swift-app-architecture:swift-architecture`

Rather than a one-off `output-dir` subcommand, add a general `config settings` command that shows and updates all global (non-repo) settings. This will grow over time as more settings move to the app level.

```bash
swift run PRRadarMacCLI config settings              # Show all general settings
swift run PRRadarMacCLI config settings set --output-dir PATH  # Update a setting
```

The `show` subcommand (default) prints key-value pairs for all general settings. The `set` subcommand accepts options for each setting field — currently just `--output-dir`, but new flags are trivially added later.

Implement as a `SettingsCommand` under `ConfigCommand` with `ShowCommand` (default) and `SetCommand` subcommands. Both read/write `AppSettings` through `SettingsService`.

Note: repo configurations continue to use their existing use case mechanism (`SaveConfigurationUseCase`, `RemoveConfigurationUseCase`, etc.) even though they share the same `SettingsView`. General settings are a separate concern and should not be mixed into those use cases.

**Files**:
- `ConfigCommand.swift` — add `SettingsCommand` with `show` and `set` subcommands
- No new use case needed — `SettingsService.load()`/`.save()` is sufficient for direct get/set

**Completed**: Created `SettingsCommand.swift` in the MacCLI Commands directory with `ShowCommand` (default) and `SetCommand` subcommands. `ShowCommand` loads settings via `SettingsService` and prints key-value pairs. `SetCommand` accepts `--output-dir` option, validates that at least one option is provided, then loads/mutates/saves settings. Registered `SettingsCommand.self` in `ConfigCommand`'s subcommands array. No use cases needed — direct `SettingsService.load()`/`.save()` is sufficient. 486 tests pass.

## - [ ] Phase 7: Validation

**Skills to read**: `swift-testing`

- Build: `swift build` must pass
- Tests: `swift test` must pass — update any tests that reference `outputDir` in `RepositoryConfigurationJSON` or `RepositoryConfiguration`
- Update test fixtures that construct `RepositoryConfiguration` with `outputDir` parameter
- Verify CLI: `swift run PRRadarMacCLI config list` shows configs without outputDir field
- Verify CLI: `swift run PRRadarMacCLI config settings` shows outputDir value
