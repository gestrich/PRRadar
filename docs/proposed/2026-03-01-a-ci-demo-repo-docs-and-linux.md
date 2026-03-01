## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, helps understand which targets are needed for CLI vs GUI |

## Background

PRRadar now has a working CI workflow in `gestrich/PRRadar-TestRepo` that runs regex-based analysis on PRs and posts inline review comments. The workflow currently runs on `macos-26` runners, which are expensive. Since the CLI doesn't use SwiftUI or macOS-specific frameworks, it should be possible to build on Linux runners instead (significantly cheaper).

This plan covers two things:
1. Documenting how the test repo workflow works so others can set up PRRadar CI
2. Investigating and implementing Linux runner support to reduce CI costs

### Current State

- **Test repo**: `gestrich/PRRadar-TestRepo` with `.github/workflows/pr-review.yml`
- **Runner**: `macos-26` (required Swift 6.2, which macOS 15 runners don't have)
- **Pipeline**: sync → prepare → analyze (regex only) → comment
- **Secrets needed**: `ANTHROPIC_API_KEY` (for prepare/focus areas), `GITHUB_TOKEN` (auto-provided)
- **Known issues fixed**: Bearer auth needed for GitHub Actions tokens, comfort-fade preview header needed for `line` param in review comment API

### Linux Blocker Analysis

Research on the codebase shows:
- **No macOS imports** in CLI/services/features/SDKs (no SwiftUI, AppKit, Security)
- **KeychainSDK** uses the `security` CLI tool (not the Security framework) — won't work on Linux but credentials come from env vars in CI anyway
- **SwiftCLI dependency** (custom fork) has `platforms: [.macOS(.v15)]` — this is the main blocker
- **OctoKit, swift-argument-parser** — both cross-platform
- **CryptoKit** — available on Linux via swift-crypto
- **MacApp target** — imports SwiftUI/MarkdownUI, must be excluded on Linux

Reference for conditional compilation: `/Users/bill/Developer/work/swift/StackAnalytics/Package.swift` uses `#if os(macOS)` to conditionally include a SwiftUI target (lines 116-130).

## Phases

## - [x] Phase 1: Write CI setup documentation

**Principles applied**: Documentation mirrors the actual test repo workflow; includes troubleshooting for known issues (Bearer auth, comfort-fade header)

Create a doc at `docs/ci-setup.md` explaining how to set up PRRadar CI in a repository. Cover:

- Prerequisites (secrets: `ANTHROPIC_API_KEY`)
- Workflow file structure (reference the test repo's `pr-review.yml`)
- Configuration step (`config add` with `--repo-path`, `--rules-dir`, `--github-account`)
- Pipeline steps: sync, prepare, analyze, comment
- The `--mode regex` flag for cost-free analysis
- Known requirements: the workflow must exist on the default branch, `pull-requests: write` permission
- Troubleshooting: Bearer auth requirement, comfort-fade preview header, rules-dir path

## - [x] Phase 2: Conditionally exclude MacApp target on Linux

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Used mutable array pattern with `#if os(macOS)` to conditionally include MacApp target, MacAppTests, and macOS-only dependencies (swift-markdown-ui, swift-markdown). All cross-platform targets remain unconditional.

Update `PRRadarLibrary/Package.swift` to conditionally exclude MacApp-related targets on Linux, following the pattern from StackAnalytics:

- Move `MacApp` target and `MacAppTests` into a `#if os(macOS)` block
- The `MacApp` library product should also be conditional
- Keep all other targets (PRRadarMacCLI, services, SDKs, features) unconditional
- The `PRRadarModels` test target should remain unconditional

Pattern to follow (from StackAnalytics):
```swift
var targets: [Target] = [ /* all cross-platform targets */ ]

#if os(macOS)
targets.append(.target(name: "MacApp", ...))
targets.append(.testTarget(name: "MacAppTests", ...))
#endif
```

## - [x] Phase 3: Add platform guard for KeychainSDK with environment-backed Linux implementation

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Protocol-based abstraction — `KeychainStoring` protocol stays cross-platform, with platform-specific implementations selected at init time.

`SecurityCLIKeychainStore` shells out to `/usr/bin/security` which doesn't exist on Linux. Rather than just no-oping, create an `EnvironmentKeychainStore` that backs the `KeychainStoring` protocol with environment variables. This way the credential resolution chain works on Linux: `SettingsService` reads from the environment store, which maps keychain key types to env var names (`*/github-token` → `GITHUB_TOKEN`, `*/anthropic-api-key` → `ANTHROPIC_API_KEY`).

Changes:
1. **KeychainSDK**: Wrap `SecurityCLIKeychainStore` in `#if os(macOS)`. Add `EnvironmentKeychainStore` (cross-platform) that reads from `ProcessInfo.processInfo.environment`. Write/remove operations throw (env vars are read-only). `allKeys()` returns keys for whichever env vars are set.
2. **SettingsService**: Update `init()` to use `SecurityCLIKeychainStore` on macOS, `EnvironmentKeychainStore` on Linux.
3. **Tests**: Add unit tests for `EnvironmentKeychainStore`.

## - [x] Phase 4: Verify SwiftCLI dependency works on Linux

**Principles applied**: Investigation over assumption — verified SPM behavior rather than blindly modifying Package.swift

The custom SwiftCLI fork at `https://github.com/gestrich/SwiftCLI.git` has `platforms: [.macOS(.v15)]` which was hypothesized to block Linux builds. Investigation found:

1. **`platforms` does NOT block Linux** — SPM ignores Apple platform constraints on Linux. Every Swift package has Linux support by default; `platforms` only sets minimum deployment targets for Apple platforms.
2. **No macOS-specific code** — All imports are cross-platform: `Foundation`, `Synchronization`, `SwiftSyntax`. No `AppKit`, `SwiftUI`, `Security`, or other macOS-only frameworks.
3. **Macros are cross-platform** — `CLIMacrosSDK` uses `SwiftCompilerPlugin` and `SwiftSyntax`, both available on Linux.
4. **`Mutex` (Synchronization)** — Requires macOS 15 on Apple platforms but is available on Linux with Swift 6.0+ (no version constraint).
5. **Removing `platforms` entirely breaks macOS builds** — SPM defaults to macOS 10.13, which is below `SwiftCompilerPlugin`'s minimum of 10.15 and `Mutex`'s requirement of macOS 15.

**Result**: No changes needed to SwiftCLI. The `platforms: [.macOS(.v15)]` constraint is correct and does not affect Linux builds.

## - [x] Phase 5: Update workflow to use Linux runner

**Principles applied**: Used `swift-actions/setup-swift@v3` for Swift installation on Ubuntu; updated both the test repo workflow and CI setup documentation to reflect Linux runner usage with macOS fallback documented

Update `PRRadar-TestRepo/.github/workflows/pr-review.yml`:

- Change `runs-on: macos-26` to `runs-on: ubuntu-latest` (or appropriate Swift 6.2 image)
- May need to install Swift 6.2 on Linux (e.g., via `swift-actions/setup-swift` or a Docker image)
- Research what Linux runners have Swift 6.2 available (may need a custom Docker image or `swiftlang/swift:nightly` image)
- Keep `macos-26` as a fallback option documented in case Linux doesn't work

## - [ ] Phase 6: Validation

- Trigger the updated workflow on PR #8 in the test repo and verify:
  - Build succeeds on Linux runner
  - All pipeline steps pass (sync, prepare, analyze, comment)
  - Inline review comments are posted to the PR
- Run `swift test` locally to ensure conditional compilation didn't break anything
- Verify MacApp still builds on macOS (`swift build` locally)
