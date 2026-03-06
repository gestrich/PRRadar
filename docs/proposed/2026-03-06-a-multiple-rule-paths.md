## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, dependency rules, placement guidance |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable model conventions |
| `/swift-testing` | Test style guide and conventions |

## Background

Currently, each repository configuration (`RepositoryConfigurationJSON`) has a single `rulesDir: String` field. This path is resolved relative to the repo and used as the sole source of review rules. Bill wants to support multiple rule paths — including paths outside the repo (e.g., a shared rules directory on the local machine). Each configuration would have a list of rule paths, one marked as default. The CLI and MacApp would allow selecting which rule path to use at runtime.

This is a **breaking change** to the settings schema. No backward compatibility is needed — existing configs will need to be re-created.

### Current Flow

1. `RepositoryConfigurationJSON.rulesDir` → single string
2. `RepositoryConfiguration.resolvedRulesDir` → resolves relative to repo path
3. CLI commands accept `--rules-dir` override
4. MacApp passes `config.resolvedRulesDir` to use cases
5. `PrepareUseCase` / `RunPipelineUseCase` accept `rulesDir: String`

### Target Flow

1. `RepositoryConfigurationJSON.rulePaths` → array of `RulePath` (name + path + isDefault)
2. `RepositoryConfiguration.resolvedDefaultRulesDir` → resolves the default rule path
3. CLI commands accept `--rules-path <name>` to select a named path (or `--rules-dir` for ad-hoc override)
4. MacApp shows a dropdown to pick which rule path to use
5. Use cases unchanged — they still receive a single `rulesDir: String`

## Phases

## - [x] Phase 1: Add RulePath Model and Update Config Models

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: RulePath model in Services layer; defaultRulePath/resolvedDefaultRulesDir on RepositoryConfiguration; validation in PrepareUseCase (Features layer) not App layer; no hardcoded values outside defaultRulePaths static

Add a new `RulePath` model and replace `rulesDir: String` with `rulePaths: [RulePath]` in the configuration models.

### Tasks

- Create `RulePath` struct in `PRRadarConfigService`:
  ```swift
  public struct RulePath: Codable, Sendable, Identifiable, Hashable {
      public let id: UUID
      public var name: String
      public var path: String
      public var isDefault: Bool
  }
  ```
- Update `RepositoryConfigurationJSON`:
  - Replace `rulesDir: String` with `rulePaths: [RulePath]`
  - Update `presentableDescription` to show all rule paths (mark default)
  - Update `init` and `init(from decoder:)`
- Update `RepositoryConfiguration`:
  - Replace `rulesDir: String` with `rulePaths: [RulePath]`
  - Replace `resolvedRulesDir` with `resolvedDefaultRulesDir` (finds the default `RulePath` and resolves it)
  - Add `resolvedRulesDir(named:)` method that looks up by name
  - Update `init(from json:...)` to map through
- Update `RepositoryConfiguration.defaultRulesDir` static to return a default `RulePath` array

### Files
- `PRRadarLibrary/Sources/services/PRRadarConfigService/RepoConfiguration.swift`
- `PRRadarLibrary/Sources/services/PRRadarConfigService/PRRadarConfig.swift`
- New: `PRRadarLibrary/Sources/services/PRRadarConfigService/RulePath.swift`

## - [x] Phase 2: Update CLI Commands

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Single `--rules-path-name` option (name-based selection, no ad-hoc path override); `resolveRulesDir` helper in Apps layer; `config add-rules-path` / `config remove-rules-path` subcommands for managing rule paths

Update CLI commands to work with the new `rulePaths` array and add a `--rules-path-name` option for selecting a named path.

### Tasks

- Update `ConfigCommand.AddCommand`:
  - Replace `--rules-dir` with `--rules-dir` (kept for the default path, creates a single-element `rulePaths` array with `isDefault: true`)
  - This keeps the simple case simple
- Update `RunCommand`, `PrepareCommand`, `RunAllCommand`:
  - Add `--rules-path <name>` option to select a named rule path from the config
  - Keep `--rules-dir` as an ad-hoc override (highest priority)
  - Resolution order: `--rules-dir` (ad-hoc) > `--rules-path` (named) > default from config
- Update `ConfigCommand` to support adding/removing rule paths (subcommands or flags):
  - `config add-rules-path <config-name> --name <name> --path <path> [--default]`
  - `config list` should display rule paths per config

### Files
- `PRRadarLibrary/Sources/apps/MacCLI/Commands/ConfigCommand.swift`
- `PRRadarLibrary/Sources/apps/MacCLI/Commands/RunCommand.swift`
- `PRRadarLibrary/Sources/apps/MacCLI/Commands/PrepareCommand.swift`
- `PRRadarLibrary/Sources/apps/MacCLI/Commands/RunAllCommand.swift`

## - [x] Phase 3: Update MacApp Settings UI

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Already implemented during Phase 1/2 — rulePathsSection with add/remove, folder picker, default toggle, and save validation all present in ConfigurationEditSheet

Update the Settings view to manage multiple rule paths per configuration.

### Tasks

- Update `ConfigurationEditSheet` in `SettingsView.swift`:
  - Replace single "Rules Dir" field with a list of rule paths
  - Each row shows name, path, and a default indicator (radio button or toggle)
  - Add/remove buttons for rule paths
  - Each path row has a folder picker (reuse existing `pathField` pattern)
  - Require at least one rule path marked as default
  - Save button disabled if no rule paths or no default selected
- Update `SettingsModel` if needed for the new data shape

### Files
- `PRRadarLibrary/Sources/apps/MacApp/UI/SettingsView.swift`
- `PRRadarLibrary/Sources/apps/MacApp/Models/SettingsModel.swift`

## - [ ] Phase 4: Update MacApp PR Review Flow

**Skills to read**: `swift-app-architecture:swift-swiftui`

Add a rule path selector to the PR review UI so users can choose which rule path to use at runtime.

### Tasks

- Add a rule path picker (dropdown) in the PR review UI (likely `PhaseInputView` or wherever the review is initiated)
  - Populated from the selected config's `rulePaths`
  - Pre-selects the default rule path
  - Selected rule path is passed through to the use case
- Update `PRModel`:
  - `runPrepare()` and any other methods that pass `config.resolvedRulesDir` should use the selected rule path instead
  - Add a `selectedRulePathID` or similar property

### Files
- `PRRadarLibrary/Sources/apps/MacApp/Models/PRModel.swift`
- `PRRadarLibrary/Sources/apps/MacApp/UI/PhaseInputView.swift`
- Possibly `PRRadarLibrary/Sources/apps/MacApp/UI/PRDetailView.swift` or similar

## - [ ] Phase 5: Update Path Resolution

**Skills to read**: `swift-app-architecture:swift-architecture`

Ensure rule paths that are absolute (e.g., `/Users/bill/shared-rules/`) are used as-is, while relative paths continue to resolve against the repo path. The existing `PathUtilities.resolve` already handles this, but verify it works correctly for the new multi-path scenario.

### Tasks

- Verify `PathUtilities.resolve` handles absolute paths outside the repo correctly (it should — it checks `isAbsolutePath`)
- Update `RuleLoaderService` if needed — it currently just takes a `rulesDir: String`, which should still work since the resolved path is passed in
- No changes expected to `PrepareUseCase` or `RunPipelineUseCase` — they already accept `rulesDir: String`

### Files
- `PRRadarLibrary/Sources/sdks/EnvironmentSDK/PathUtilities.swift` (verify only)
- `PRRadarLibrary/Sources/services/PRRadarCLIService/RuleLoaderService.swift` (verify only)

## - [ ] Phase 6: Validation

**Skills to read**: `swift-testing`

### Tasks

- Run `swift build` — ensure everything compiles
- Run `swift test` — ensure existing tests pass (update any that reference `rulesDir`)
- Update any model tests that construct `RepositoryConfigurationJSON` or `RepositoryConfiguration` to use the new `rulePaths` API
- Add tests for:
  - `RulePath` model encoding/decoding
  - `RepositoryConfiguration.resolvedDefaultRulesDir` with various path types (relative, absolute, `~`)
  - `resolvedRulesDir(named:)` lookup
- Manual CLI verification:
  - `swift run PRRadarMacCLI config add ...` with rule paths
  - `swift run PRRadarMacCLI config list` shows rule paths
  - `swift run PRRadarMacCLI run 1 --config test-repo --rules-path <name>` uses the named path
- Manual MacApp verification:
  - Settings: add/edit/remove rule paths
  - PR review: dropdown selects rule path, review uses correct rules
