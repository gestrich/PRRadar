## Relevant Skills

| Skill | Description |
|-------|-------------|
| `pr-radar-debug` | Debugging context for configured repos, rule dirs, output files, CLI commands |
| `pr-radar-add-rule` | Rule creation workflow (frontmatter, scripts, verification) |

## Background

We created a new script-based rule (`swiftui-localization-bundle`) that detects SwiftUI views in Swift packages that are missing `bundle: .module` for correct localization. The script and rule file work correctly in isolation, but the `analyze` CLI command hangs when trying to run it end-to-end.

### What Was Created

**Rule file:** `/Users/bill/Desktop/pr-radar-experimental-rules/apis-apple/swiftui-localization-bundle.md`
- Script-based rule, `new_code_lines_only: true`
- Grep patterns use escaped parens (e.g., `Text\\(`) since PRRadar treats them as regex (`NSRegularExpression`)
- Applies to `*.swift` files

**Script:** `/Users/bill/Desktop/pr-radar-experimental-rules/apis-apple/check-swiftui-localization.sh`
- Walks parent directories for `Package.swift` — exits early if not in a package
- Checks `Text(`, `Label(`, `Button(`, `Toggle(`, `Picker(`, `Section(`, `Link(`, `NavigationLink(`, `Menu(`, and modifiers like `.navigationTitle(`, `.confirmationDialog(`, `.alert(`, `.accessibilityLabel(`
- Skips lines with `bundle:`, `verbatim:`, comments, and preview code

**Test fixture:** Committed and pushed to PR #19053 in the ios repo (`jeppesen-foreflight/ff-ios`)
- Branch: `test/2026-03/bg/pr-radar-nullability-tests`
- Files added:
  - `code-review-rules/test-fixtures/swiftui-localization/Package.swift` (fake package)
  - `code-review-rules/test-fixtures/swiftui-localization/Sources/SwiftUILocalizationExample.swift`
- Commit: `07c53fae3c9`

### What Works

1. **Script runs correctly standalone:**
   ```bash
   /Users/bill/Desktop/pr-radar-experimental-rules/apis-apple/check-swiftui-localization.sh \
     /Users/bill/Developer/work/ios-auto/code-review-rules/test-fixtures/swiftui-localization/Sources/SwiftUILocalizationExample.swift \
     1 55
   ```
   Produces 13 violations. Correctly skips `bundle: .module` and `verbatim:` lines. Correctly skips files not inside a Swift package.

2. **Rule loads into PRRadar:**
   ```bash
   cd PRRadarLibrary
   swift run PRRadarMacCLI sync 19053 --config ios
   swift run PRRadarMacCLI prepare 19053 --config ios --rules-path-name experiment --json
   ```
   Output: `{"focus_areas": 9, "rules": 8, "tasks": 13}` — the `swiftui-localization-bundle` rule created 2 tasks.

3. **Prepare phase output** is at:
   ```
   ~/Desktop/code-reviews/19053/analysis/07c53fa/prepare/tasks/
   ```
   Contains `data-swiftui-localization-bundle_*.json` task files.

### What Hangs

The `analyze` command hangs after building, producing no output:

```bash
# All of these hang:
swift run PRRadarMacCLI analyze 19053 --config ios --rule swiftui-localization-bundle --mode script --quiet --json
swift run PRRadarMacCLI analyze 19053 --config ios --mode script --quiet --json
swift run PRRadarMacCLI analyze 19053 --config ios --rule swiftui-localization-bundle --mode script
```

The `status` command confirms evaluate has not started:
```bash
swift run PRRadarMacCLI status 19053 --config ios
# Shows: evaluate = "not started"
```

### What We Know About the Hang

- The `AnalyzeCommand.run()` method at `Sources/apps/MacCLI/Commands/AnalyzeCommand.swift:33` calls `resolveConfigFromOptions`, then `PrepareUseCase.parseOutput`, then `AnalyzeUseCase.execute()`.
- Debug logging was partially added to `AnalyzeCommand.run()` but not yet tested (was interrupted).
- The `AnalyzeUseCase` (at `Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift`) creates an `AsyncThrowingStream`. For script tasks, it calls `checkoutPRCommit()` which does `git fetch origin pull/19053/head` + `git checkout`. The fetch itself works fine standalone (`--dry-run` succeeds).
- Possible causes: the `AsyncThrowingStream` continuation might not be yielding, the checkout might be blocking on git interactive prompts, or there's a deadlock in the stream setup.

## Phases

## - [x] Phase 1: Identify the hang point with debug logging

**Skills used**: `pr-radar-debug`
**Findings**: Added debug logging through AnalyzeCommand → AnalyzeUseCase → AnalyzeSingleTaskUseCase. The hang occurred inside `ScriptAnalysisService.analyzeTask()` when running the shell script via `Process`. The script's `is_in_swift_package()` function entered an infinite loop because `dirname` on a relative path reaches `"."`, and `dirname "."` returns `"."` forever — never reaching `"/"` to exit the while loop.

## - [x] Phase 2: Fix the hang

**Fix**: Changed `check-swiftui-localization.sh` line 20 from `dir="$(dirname "$1")"` to `dir="$(cd "$(dirname "$1")" && pwd)"` to resolve relative paths to absolute before walking parent directories.

## - [x] Phase 3: Verify end-to-end

Ran `swift run PRRadarMacCLI analyze 19053 --config ios --rule swiftui-localization-bundle --mode script` successfully. Results: 13 violations in `SwiftUILocalizationExample.swift`, 0 in `StateExample.swift` (correctly skipped — no Package.swift in parents).

## - [x] Phase 4: Cleanup

- Removed all debug logging from `AnalyzeCommand.swift` and `AnalyzeUseCase.swift`
- ios repo working tree clean
- All 728 tests pass
