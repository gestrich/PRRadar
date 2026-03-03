## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-testing` | Test style guide and conventions |
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules for code placement |

## Compatibility

Prerequisite: `2026-03-01-c-unified-line-classification.md` (completed) — provides `ClassifiedDiffLine`, `ClassifiedHunk`, and per-line classification.

## Background

The `grep` pre-filter in rule matching silently drops ObjC method declarations because of a collision between diff `+`/`-` prefixes and ObjC method prefixes (`-` for instance, `+` for class methods).

### The Bug

When `Hunk.extractChangedContent()` processes annotated-format diff lines like `  70: +- (UITabBarItem *)foo;`, it:
1. Finds `": +"` in the string
2. Extracts everything after it: `- (UITabBarItem *)foo;`
3. Prepends a diff `+` marker: `"+- (UITabBarItem *)foo;"`

The nullability rules' grep pattern `^[+-]\s*\(` then fails because:
- `^[+-]` matches the diff `+`
- `\s*` expects whitespace but finds `-` (the ObjC method prefix)

This means **every new ObjC method declaration is invisible to the grep pre-filter**. Tasks are only created when a focus area also contains `@property` or `@interface` lines.

### The Design Conflict

Two different conventions exist in the current grep patterns:
- **Source-code patterns**: `^[+-]\s*\(` in nullability rules treats `[+-]` as the ObjC method prefix
- **Diff-aware patterns**: `^\+.*@import` in import-order-objc treats `\+` as the diff "added line" marker

These are mutually exclusive assumptions about the format of the content being matched.

### The Fix

Replace the `extractChangedContent`-based grep filtering with classified line data from the unified line classification model (`ClassifiedDiffLine`/`ClassifiedHunk`). The `RegexAnalysisService` already uses this approach — grep filtering should use the same data path.

`ClassifiedDiffLine.content` is clean source code (no diff prefix), and `ClassifiedDiffLine.classification` tells you exactly what happened to each line. This eliminates the prefix collision entirely and also allows the grep filter to skip moved code (which doesn't need evaluation).

This requires:
- Threading `[ClassifiedHunk]` into the grep filtering path
- Updating the one rule (`import-order-objc`) that relies on the diff prefix in its grep pattern
- Removing the now-unused `extractChangedContent`

## Phases

## - [x] Phase 1: Move `filterHunksForFocusArea` to `ClassifiedHunk`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Moved pure function on model types to Models layer per architecture rules; removed service method entirely since no external consumers

**Skills to read**: `swift-app-architecture:swift-architecture`

`RegexAnalysisService.filterHunksForFocusArea` is a pure function on model types (`[ClassifiedHunk]` + `FocusArea` → `[ClassifiedHunk]`). Move it to the model layer so both `RuleLoaderService` (grep filtering) and `RegexAnalysisService` (regex evaluation) can use it without cross-service coupling.

**File**: `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift`

Add a static method to `ClassifiedHunk`:
```swift
public static func filterForFocusArea(_ hunks: [ClassifiedHunk], focusArea: FocusArea) -> [ClassifiedHunk]
```

Logic is identical to `RegexAnalysisService.filterHunksForFocusArea` — filter by file path, then filter lines by line number within `[startLine, endLine]`.

**File**: `PRRadarLibrary/Sources/services/PRRadarCLIService/RegexAnalysisService.swift`

Update `RegexAnalysisService.filterHunksForFocusArea` to delegate to `ClassifiedHunk.filterForFocusArea` (or remove it and update callers to call the model method directly).

## - [x] Phase 2: Update `filterRulesForFocusArea` to use classified hunks

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Service method accepts model types directly; grep patterns now run against clean source content from `ClassifiedHunk.changedLines`

**Skills to read**: `swift-app-architecture:swift-architecture`

Change `RuleLoaderService.filterRulesForFocusArea` to accept `[ClassifiedHunk]` and use classified line content for grep matching instead of `extractChangedContent`.

**File**: `PRRadarLibrary/Sources/services/PRRadarCLIService/RuleLoaderService.swift`

Change the signature:
```swift
public func filterRulesForFocusArea(
    _ allRules: [ReviewRule],
    focusArea: FocusArea,
    classifiedHunks: [ClassifiedHunk]
) -> [ReviewRule]
```

Implementation:
1. Call `ClassifiedHunk.filterForFocusArea(classifiedHunks, focusArea: focusArea)` once
2. Extract changed lines (`.new`, `.removed`, `.changedInMove`) and join their `.content` with newlines
3. Pass to `rule.matchesDiffContent()` as before — `GrepPatterns.matches` is unchanged

The grep patterns now run against clean source code. Context lines and moved code are excluded by classification.

## - [x] Phase 3: Thread classified hunks through `TaskCreatorService`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Threaded classified hunks from feature layer through service layer; made `SyncSnapshot.classifiedHunks` non-optional since sync always produces the file; updated tests to pass required parameter

**Skills to read**: `swift-app-architecture:swift-architecture`

`TaskCreatorService.createTasks` calls `filterRulesForFocusArea` — it needs the classified hunks.

**File**: `PRRadarLibrary/Sources/services/PRRadarCLIService/TaskCreatorService.swift`

Add `classifiedHunks: [ClassifiedHunk]` parameter to `createTasks` and `createAndWriteTasks`. Pass through to `filterRulesForFocusArea`.

**File**: `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/PrepareUseCase.swift`

The `diffSnapshot` (`SyncSnapshot`) already has `classifiedHunks`. Pass `diffSnapshot.classifiedHunks ?? []` to `createAndWriteTasks`.

**File**: `PRRadarLibrary/Sources/apps/MacCLI/Commands/PrepareCommand.swift` (if it calls `createTasks` directly)

Check for any other callers and thread classified hunks through.

## - [x] Phase 4: Update import-order-objc grep pattern

**Skills used**: none
**Principles applied**: Removed diff prefix assumption from external rule; PR created at https://github.com/jeppesen-foreflight/ff-ios/pull/19048

**Skills to read**: none

The `import-order-objc` rule's grep pattern `^\+.*@import` relies on the diff prefix to match only added `@import` lines. Since the grep filter now runs against clean source content, change this to just `@import`.

**File**: `code-review-rules/apis-apple/import-order-objc.md` (in the ios-auto repo — outside this repo)

Change:
```yaml
grep:
  any:
    - "^\\+.*@import"
```
To:
```yaml
grep:
  any:
    - "@import"
```

This is safe because the classified line data only includes changed lines (not context), so the grep filter doesn't need the `\+` prefix to limit to new content.

**Note**: This file is in an external rules repo. Document the required change and apply it separately.

## - [x] Phase 5: Remove `extractChangedContent`

**Skills used**: none
**Principles applied**: Removed `getChangedContent()` and `extractChangedContent(from:)` from Hunk; kept `getFocusedContent()` which is still used by AnalysisService for evaluation prompts

**Skills to read**: none

With the grep filter using classified hunks, `Hunk.extractChangedContent` and `FocusArea.getFocusedContent` (which was only called by the grep filter) may be unused.

**File**: `PRRadarLibrary/Sources/services/PRRadarModels/GitDiffModels/Hunk.swift`

Check if `extractChangedContent` has any remaining callers. If not, remove it.

**File**: `PRRadarLibrary/Sources/services/PRRadarModels/FocusAreaOutput.swift`

Check if `getFocusedContent` has any remaining callers. If not, remove it. (`getContextAroundLine` may still be needed.)

## - [ ] Phase 6: Update tests

**Skills to read**: `swift-testing`

**File**: `PRRadarLibrary/Tests/PRRadarModelsTests/HunkBehaviorTests.swift`

Remove or update `extractChangedContentRaw` and `extractChangedContentAnnotated` tests (if `extractChangedContent` was removed).

**File**: `PRRadarLibrary/Tests/PRRadarCLIServiceTests/` (or appropriate test location)

Add tests for the new grep filtering path:
- A rule with grep pattern `^[+-]\s*\(` matches a classified hunk containing an ObjC instance method `- (UITabBarItem *)foo;` classified as `.new` — this is the regression test for the original bug
- A rule with grep pattern `@import` matches a classified hunk with an added `@import UIKit` line
- Moved lines (`.moved`, `.movedRemoval`) are excluded from grep matching
- Context lines (`.context`) are excluded from grep matching

**File**: `PRRadarLibrary/Tests/PRRadarModelsTests/ClassifiedDiffLineTests.swift` (or new file)

Add tests for `ClassifiedHunk.filterForFocusArea` (same logic as the existing `RegexAnalysisService` tests, now at the model layer).

## - [ ] Phase 7: Validation

**Skills to read**: `swift-testing`

1. Run `swift test` — all existing and new tests pass
2. Run `swift build` — clean build
3. Run `swift run PRRadarMacCLI analyze 1 --config test-repo` — verify the prepare step creates tasks correctly
4. Verify that `.h` files with ObjC method declarations get matched by nullability grep patterns
