## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, placement guidance, dependency rules |
| `/swift-testing` | Test style guide and conventions |

## Prerequisites

- **`2026-03-01-b-effective-diff-pipeline.md`** — Wiring up the effective diff pipeline and verifying the MacApp view. Must be completed first so that "new code only" filtering has real effective diff data to work with.
- **`2026-03-01-c-unified-line-classification.md`** — Unified per-line classification model. Must be completed first so that "new code only" filtering can use `ClassifiedDiffLine` instead of ad-hoc extraction from multiple sources.

## Compatibility

No backwards compatibility is needed for any data formats, APIs, or serialized outputs. This is all new functionality — existing models, YAML schemas, and JSON outputs can be changed freely without migration concerns.

## Background

PRRadar currently evaluates rules exclusively through AI (Claude Agent SDK). Bill wants to support **regex-based rule evaluation** as a lightweight, no-AI alternative. This would allow rules to define a `violation_regex` in their YAML frontmatter — when that regex matches, a violation is produced without any AI call.

A key foundational requirement is the ability to restrict analysis to **only new code** (not moved or modified lines). The effective diff pipeline (covered in the prerequisite plan) provides the data needed to distinguish truly new code from moved code.

### Test repo

A test repository is available at `/Users/bill/Developer/personal/PRRadar-TestRepo` with the CLI config `test-repo`. Use this to verify changes against real PR diffs throughout implementation:
```bash
cd PRRadarLibrary
swift run PRRadarMacCLI diff 1 --config test-repo
swift run PRRadarMacCLI analyze 1 --config test-repo
```
The `/pr-radar-verify-work` skill can also be used to run the CLI against the test repo.

### Key findings from codebase exploration

1. **Rule YAML uses a custom parser**: `parseSimpleYAML()` in `RuleOutput.swift` handles frontmatter — supports top-level keys, one level of nesting, inline arrays, and list items. New fields like `violation_regex` and `new_code_lines_only` can be added here.

2. **Existing `grep` field filters applicability, not violations**: The `GrepPatterns` struct matches diff content to decide if a rule applies. The new `violation_regex` serves a different purpose — it's the actual analysis mechanism.

3. **`DiffLine` already has `.added` type with line numbers**: `Hunk.getDiffLines()` returns `DiffLine` objects with `lineType: .added` and `newLineNumber`. This is the building block for "new code only" filtering.

4. **The unified line classification system distinguishes moved code**: `ClassifiedDiffLine` assigns each line a `LineClassification` (`.new`, `.moved`, `.changedInMove`, `.removed`, `.movedRemoval`, `.context`). Filtering for "new code only" is a single filter on classification rather than combining multiple systems.

## Phases

## - [ ] Phase 1: Add `new_code_lines_only` option to rule YAML schema

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add a new `new_code_lines_only` boolean field to the rule frontmatter schema. When set to `true`, analysis (both AI and regex) should only consider truly new lines of code — not moved or modified lines.

**Tasks:**
- Add `newCodeLinesOnly: Bool` property to `ReviewRule` (default `false`)
- Parse `new_code_lines_only` from YAML frontmatter in `ReviewRule.fromFile()`
- Add `newCodeLinesOnly` to `ReviewRule.CodingKeys` for JSON serialization
- Propagate to `TaskRule` so it's available during evaluation
- Add to `RuleRequest.from()` mapping

**Files to modify:**
- `PRRadarLibrary/Sources/services/PRRadarModels/RuleOutput.swift` (ReviewRule struct and fromFile parser)
- `PRRadarLibrary/Sources/services/PRRadarModels/RuleRequest.swift` (TaskRule struct)

## - [ ] Phase 2: Implement "new code only" line filtering

**Skills to read**: `/swift-app-architecture:swift-architecture`

Build a utility to extract only truly new lines from the classified diff data. The unified classification model (`ClassifiedDiffLine`) already assigns each line a `LineClassification`, so "new code only" filtering is a simple filter operation.

"New code lines" are lines classified as:
- `.new` — genuinely new added lines not part of any move
- `.changedInMove` — new lines added inside a moved block (e.g. a line inserted in the middle of a moved method)

**Tasks:**
- Add a utility function (e.g. `extractNewCodeLines(from: [ClassifiedHunk]) -> [ClassifiedDiffLine]`) in `PRRadarModels`
- Filter classified lines where `classification == .new || classification == .changedInMove`
- The result should be usable both for regex evaluation and for filtering AI evaluation scope
- The `ClassifiedHunk.newCodeLines` and `ClassifiedHunk.hasNewCode` computed properties already exist and can be used directly — this utility just flattens across all hunks

**Files to modify:**
- `PRRadarLibrary/Sources/services/PRRadarModels/EffectiveDiff/ClassifiedDiffLine.swift` (add utility function)

## - [ ] Phase 3: Add `violation_regex` field to rule YAML schema

**Skills to read**: `/swift-app-architecture:swift-architecture`

Add a new `violation_regex` field to the rule frontmatter. When present, this regex is used for the actual rule evaluation instead of AI. A match means a violation.

**Tasks:**
- Add `violationRegex: String?` property to `ReviewRule`
- Parse `violation_regex` from YAML frontmatter in `ReviewRule.fromFile()`
- Add to `CodingKeys` for JSON serialization
- Propagate to `TaskRule` so it's available during evaluation
- Add a computed property like `isRegexOnly: Bool` that returns `true` when `violationRegex` is non-nil (these rules don't need AI)

**Files to modify:**
- `PRRadarLibrary/Sources/services/PRRadarModels/RuleOutput.swift`
- `PRRadarLibrary/Sources/services/PRRadarModels/RuleRequest.swift`

## - [ ] Phase 4: Implement regex-based evaluation service

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create a `RegexAnalysisService` that evaluates rules using their `violation_regex` against diff content. Produces the same `RuleOutcome` output as `AnalysisService`.

**Tasks:**
- Create `RegexAnalysisService` in `PRRadarCLIService/`
- Method signature: `func analyzeTask(_ task: RuleRequest, classifiedHunks: [ClassifiedHunk]) -> RuleOutcome`
- When `newCodeLinesOnly` is true on the rule, filter to lines where `classification == .new || classification == .changedInMove` (using the Phase 2 utility or `ClassifiedHunk.newCodeLines`); otherwise use all changed lines (`ClassifiedHunk.changedLines`)
- Run `NSRegularExpression` with the `violation_regex` against each line's `content`
- For each match, create a `Violation` with: score (configurable, default e.g. 5), comment (from rule description or a configurable message template), file path (from `ClassifiedDiffLine.filePath`), and line number (from `ClassifiedDiffLine.newLineNumber` or `oldLineNumber`)
- Return a `RuleResult` with `modelUsed: "regex"`, `durationMs` from timing, `costUsd: 0`

**Files to create:**
- `PRRadarLibrary/Sources/services/PRRadarCLIService/RegexAnalysisService.swift`

## - [ ] Phase 5: Integrate regex evaluation into the analysis pipeline

**Skills to read**: `/swift-app-architecture:swift-architecture`

Route tasks with `violation_regex` rules to the regex service instead of the AI service.

**Tasks:**
- In `AnalyzeUseCase.swift`, before calling `AnalysisService`, check if the task's rule has a `violationRegex`
- If yes, route to `RegexAnalysisService` instead of `AnalysisService`, passing `classifiedHunks` from `EffectiveDiffPipelineResult`
- The result should be written to the same evaluations directory in the same format
- In `AnalyzeSingleTaskUseCase.swift`, add the same routing logic
- In `AnalysisService.runBatchAnalysis()`, partition tasks into AI vs regex, run regex tasks first (instant), then AI tasks
- Ensure cached evaluation logic in `AnalysisCacheService` works the same for regex results

**Files to modify:**
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/AnalyzeUseCase.swift`
- `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/AnalyzeSingleTaskUseCase.swift`
- `PRRadarLibrary/Sources/services/PRRadarCLIService/AnalysisService.swift`

## - [ ] Phase 6: Create test rule and verify end-to-end with test repo

Verify the full pipeline works with a regex-only rule using the test repo at `/Users/bill/Developer/personal/PRRadar-TestRepo`.

**Tasks:**
- Create a test rule in the test repo's rules directory, e.g. `detect-force-unwrap.md`:
  ```yaml
  ---
  description: Avoid force unwrapping optionals
  category: safety
  new_code_lines_only: true
  violation_regex: "![^=]"
  applies_to:
    file_patterns: ["*.swift"]
  ---
  Force unwrapping can cause crashes. Use optional binding or nil coalescing instead.
  ```
- Run the full pipeline against the test repo: `cd PRRadarLibrary && swift run PRRadarMacCLI analyze 1 --config test-repo`
- Verify regex violations appear in the evaluation output JSON
- Run `swift run PRRadarMacCLI report 1 --config test-repo` and verify the report picks up the violations
- Run `swift run PRRadarMacCLI comment 1 --config test-repo` and verify comment generation works for regex violations

## - [ ] Phase 7: Validation

**Skills to read**: `/swift-testing`

**Tasks:**
- Add unit tests for the new `ReviewRule` fields (`newCodeLinesOnly`, `violationRegex`) — parsing from YAML, default values, serialization round-trip
- Add unit tests for `RegexAnalysisService` — matching, no-match, multi-match, new-code-only filtering via `ClassifiedDiffLine` classification
- Add unit tests for "new code only" line extraction (filtering `ClassifiedDiffLine` by `.new` and `.changedInMove`)
- Add unit tests verifying the pipeline routing (regex vs AI) based on rule configuration
- Run full test suite: `cd PRRadarLibrary && swift test`
- Build check: `cd PRRadarLibrary && swift build`
- Final end-to-end check against the test repo: `cd PRRadarLibrary && swift run PRRadarMacCLI analyze 1 --config test-repo`
