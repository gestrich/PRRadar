# Script Analysis Support

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-testing` | Test style guide and conventions |

## Background

PRRadar currently supports two analysis methods for evaluating PR code against rules:

1. **AI analysis** — Sends a prompt to Claude via the agent SDK. Determined implicitly when `violationRegex` is not set.
2. **Regex analysis** — Matches a regex pattern against diff lines. Determined implicitly when `violationRegex` is set on the rule.

The dispatch logic in `AnalysisService.runBatchAnalysis` uses `isRegexOnly` (a bool computed from `violationRegex != nil`) to route between these two paths. `AnalysisMode` offers filtering (`all`, `regex`, `ai`).

Bill wants to add a **third analysis type: scripts**. A rule's YAML frontmatter would specify a script path (relative to the repo). The script runs against a file and outputs violations — just like a linter. PRRadar then post-filters those violations against the PR's changed lines. Example use case: checking that `@import` statements are in sorted order.

Since we're going from 2 to 3 analysis types, this is the right time to refactor the implicit type detection (`isRegexOnly` bool) into a proper abstraction. The goal: the script type should feel like a first-class peer to AI and regex, not a bolt-on hack.

### Key Design Decisions

**Scripts are linters, not diff-aware tools.** A script receives a file path, runs its check against the file on disk, and outputs violations. It knows nothing about the diff, changed lines, or PR context. PRRadar handles all the diff-awareness:

1. Script runs on the file → produces violations (line number + message)
2. PRRadar post-filters violations against changed lines based on `newCodeLinesOnly`:
   - `newCodeLinesOnly: true` → only keep violations on lines with `changeKind == .added` (genuinely new code, including new insertions inside moved blocks)
   - `newCodeLinesOnly: false` → keep violations on all changed lines (`changeKind != .unchanged`)
3. Violations on untouched lines are discarded

**"You touched it, you own it" philosophy.** If a line was modified and the script flags it, the violation stands — even if the flagged issue predates the change. This matches how linter CI integrations work industry-wide (SwiftLint, ESLint, etc.) and avoids character-level diff complexity. The `newCodeLinesOnly` flag already provides the knob to tune sensitivity.

**Script I/O — minimal contract:**

Invocation:
```bash
./scripts/check-import-order.sh path/to/file.swift 15 30
```

The script receives three positional arguments:
1. **File path** — relative to repo root (matching how paths appear in diffs)
2. **Start line** — first line of the focus area (integer)
3. **End line** — last line of the focus area (integer)

The working directory is set to the repo root, so the script can access any repo file. Scripts may use the line range to scope their analysis (e.g., only check imports in that region) or ignore it entirely and analyze the whole file — PRRadar post-filters violations against changed lines regardless.

Output (stdout, one violation per line, tab-delimited, 3 or 4 columns):
```
15	8	5	Import @import ZModule should come before @import BModule
23	1	3
```

Format: `LINE_NUMBER<TAB>CHARACTER_POSITION<TAB>SCORE[<TAB>COMMENT]`

- `LINE_NUMBER`: Line number in the file where the violation occurs (required, must be a positive integer)
- `CHARACTER_POSITION`: Column/character offset within the line (required, must be a non-negative integer; use `0` or `1` if not meaningful)
- `SCORE`: Severity 1-10 (required, same scale as AI/regex violations)
- `COMMENT`: Human-readable description for the GitHub PR comment (optional — if omitted, falls back to `rule.violationMessage ?? rule.description`, same as regex analysis)

Exit codes:
- 0 = success (read violations from stdout; empty stdout = no violations)
- Non-zero = error (capture stderr as error message, produce `RuleError`)

**Strict parsing**: Every non-empty stdout line must have exactly 3 or 4 tab-delimited columns. If any line fails validation (wrong column count, non-integer line number, non-integer character position, non-integer or out-of-range score), parsing throws an error for the entire script result — no partial results. This catches misconfigured scripts early rather than silently dropping violations.

This contract is trivially implementable in any language — a bash script, a python one-liner, or an existing linter wrapped with `awk`.

**Rule YAML format** — new field `violation_script`:
```yaml
---
description: Imports must be alphabetically ordered
category: style
focus_type: file
applies_to:
  file_patterns: ["*.swift", "*.m"]
grep:
  any: ["@import", "import "]
new_code_lines_only: true
violation_script: scripts/check-import-order.sh
---
```

Detection logic (order of precedence):
1. `violation_script` set → script analysis
2. `violation_regex` set → regex analysis
3. Neither → AI analysis

A rule cannot have both `violation_script` and `violation_regex` set.

### Prerequisite

The line classification refactor (2026-03-03-b) has been completed. `LineClassification` has been replaced with a two-axis model (`ChangeKind` + `inMovedBlock: Bool`). The `newCodeLinesOnly` filter logic in `ScriptAnalysisService` should use `changeKind == .added` (as `RegexAnalysisService` already does). Services accept `AnnotatedDiff` (which bundles `classifiedHunks`, `fullDiff`, `effectiveDiff`, and `moveReport`) rather than separate `classifiedHunks` parameters.

## Phases

## - [ ] Phase 1: Introduce `RuleAnalysisType` enum and refactor dispatch

**Skills to read**: `/swift-app-architecture:swift-architecture`

Replace the implicit `isRegexOnly: Bool` pattern with a proper enum.

### Models layer (`PRRadarModels`)

1. **Create `RuleAnalysisType` enum** in a new file `PRRadarModels/Evaluations/RuleAnalysisType.swift`:
   ```swift
   public enum RuleAnalysisType: Sendable, Equatable {
       case ai
       case regex
       case script
   }
   ```
   Pure discriminator — no associated values. Execution details (`violationRegex`, `violationScript`, `model`, etc.) stay on the rule where they're already stored. Make it `Codable` with a `type` discriminator (same pattern as `AnalysisMethod`).

2. **Add computed `analysisType` to `ReviewRule` and `TaskRule`** replacing `isRegexOnly`:
   ```swift
   public var analysisType: RuleAnalysisType {
       if violationScript != nil { return .script }
       if violationRegex != nil { return .regex }
       return .ai
   }
   ```
   Remove `isRegexOnly` — all callers are updated in this phase.

3. **Add `relevantLines(newCodeLinesOnly:)` and `relevantLineNumbers(newCodeLinesOnly:)` to `ClassifiedHunk`**:
   ```swift
   public func relevantLines(newCodeLinesOnly: Bool) -> [ClassifiedDiffLine] {
       newCodeLinesOnly ? newCodeLines : changedLines
   }

   public func relevantLineNumbers(newCodeLinesOnly: Bool) -> Set<Int> {
       Set(relevantLines(newCodeLinesOnly: newCodeLinesOnly)
           .compactMap { $0.newLineNumber ?? $0.oldLineNumber })
   }
   ```
   `relevantLines` is used by `RegexAnalysisService` (replaces its inline filter). `relevantLineNumbers` is used by `ScriptAnalysisService` (post-filter by line number).

4. **Refactor `RegexAnalysisService`** to use `hunk.relevantLines(newCodeLinesOnly:)` instead of the inline `newCodeLinesOnly` branching logic.

5. **Refactor `AnalysisMode`** to use `RuleAnalysisType` instead of `isRegexOnly`:
   - Add `.scriptOnly = "script"` case
   - Update `matches(_:)` to compare against `task.rule.analysisType`

### Services layer (`PRRadarCLIService`)

6. **Refactor `AnalysisService.runBatchAnalysis`** dispatch:
   - Replace `if let pattern = task.rule.violationRegex` with a `switch task.rule.analysisType`
   - Read `violationRegex`/`violationScript` from the rule as needed in each case
   - Group tasks by analysis type: regex first (instant), scripts next (fast), AI last (expensive)
   - For now, the `.script` case can throw a "not yet implemented" error

7. **Remove `isRegexOnly` references** — update all remaining callers to use `analysisType`.

### Apps layer

8. **Update CLI argument parsing** for `--mode` flag to accept `"script"` alongside `"regex"` and `"ai"`.

## - [ ] Phase 2: Add script fields to models and YAML parsing

**Skills to read**: `/swift-app-architecture:swift-architecture`

1. **Add `violationScript: String?` field** to `ReviewRule`:
   - Add to the stored properties, `CodingKeys`, `init(from:)` decoder, and `init(...)` parameter list
   - Add to YAML frontmatter parsing in `fromFile(_:)`

2. **Add `violationScript: String?` field** to `TaskRule`:
   - Same changes: stored property, `CodingKeys`, `init(from:)`, `init(...)`

3. **Add `AnalysisMethod.script(path: String)` case**:
   - Update `displayName` to return `"Script"`
   - Update `costUsd` to return `0`
   - Update `Codable` conformance with `"script"` type discriminator

4. **Validation in `ReviewRule.fromFile`**: If both `violationScript` and `violationRegex` are set, throw a parsing error.

5. **Add example rule** in `docs/rule-examples/import-order-script.md` showing the `violation_script` YAML format.

## - [ ] Phase 3: Implement `ScriptAnalysisService`

**Skills to read**: `/swift-app-architecture:swift-architecture`

Create `PRRadarCLIService/ScriptAnalysisService.swift` parallel to `RegexAnalysisService`.

1. **Implement `analyzeTask` method**:
   - Resolve script path: `repoPath + "/" + scriptRelativePath`
   - Verify script exists and is executable
   - Launch script as a `Process`:
     - Executable: the resolved script path
     - Arguments: `[task.focusArea.filePath, "\(task.focusArea.startLine)", "\(task.focusArea.endLine)"]`
     - Working directory: `repoPath`
     - Stdout pipe: capture output
     - Stderr pipe: capture errors
   - Wait for process completion with a timeout (default 30 seconds)
   - On exit code 0: parse stdout as tab-delimited violations (one per line: `LINE\tCHAR\tSCORE` or `LINE\tCHAR\tSCORE\tCOMMENT`), produce raw `[Violation]` list
   - On non-zero exit: return `RuleError` with stderr content
   - Return `RuleResult` with `.script(path:)` analysis method

2. **Post-filter violations against changed lines**:
   - Get the classified hunks for this task's focus area (same `ClassifiedHunk.filterForFocusArea` used by regex)
   - Use `hunk.relevantLineNumbers(newCodeLinesOnly: task.rule.newCodeLinesOnly)` to build the set of line numbers to keep (added in Phase 1)
   - Drop any script violations whose `lineNumber` is not in the relevant set

3. **TSV parsing — strict mode**: Parse each non-empty stdout line as `LINE_NUMBER<TAB>CHARACTER_POSITION<TAB>SCORE[<TAB>COMMENT]`.
   - Every non-empty line must have exactly 3 or 4 tab-delimited columns
   - `LINE_NUMBER` must be a positive integer
   - `CHARACTER_POSITION` must be a non-negative integer
   - `SCORE` must be an integer 1-10
   - `COMMENT` (4th column) is optional; if absent, use `rule.violationMessage ?? rule.description`
   - If any line fails validation, throw a `RuleError` for the entire script result — no partial results, no silent skipping
   - Empty lines are skipped (trailing newline is common)

## - [ ] Phase 4: Wire script analysis into the pipeline

**Skills to read**: `/swift-app-architecture:swift-architecture`

1. **Update `AnalysisService.runBatchAnalysis`** `.script` case:
   - Replace the placeholder error with actual `ScriptAnalysisService` call
   - Pass `repoPath` and `annotatedDiff`
   - Write result JSON to evals directory (same file naming pattern)

2. **Task ordering**: Group tasks as regex → script → AI. Both regex and script are local/instant relative to AI, so they run first for fast feedback.

3. **Error handling**: Wrap script execution errors (file not found, not executable, timeout, malformed output) into `RuleError` with descriptive messages.

4. **Verify end-to-end flow**: The prepare → analyze pipeline should work with a script rule. The rule YAML `violation_script` field gets parsed into `ReviewRule`, carried through to `TaskRule` in `RuleRequest`, and dispatched to `ScriptAnalysisService` during analysis.

## - [ ] Phase 5: Tests

**Skills to read**: `/swift-testing`

1. **`RuleAnalysisType` tests**:
   - Codable round-trip for each case
   - `analysisType` computed property on `ReviewRule` for all three cases
   - Precedence: script wins over regex when both set (though Phase 2 adds validation to prevent this)

2. **`ClassifiedHunk.relevantLines/relevantLineNumbers` tests**:
   - `newCodeLinesOnly: true` → only `changeKind == .added` lines
   - `newCodeLinesOnly: false` → all lines with `changeKind != .unchanged`
   - `relevantLineNumbers` returns correct `Set<Int>` for each mode

3. **`AnalysisMode` tests**:
   - `.scriptOnly` filtering
   - `.all` still matches script tasks

4. **YAML parsing tests**:
   - Rule with `violation_script` field
   - Validation error when both `violation_script` and `violation_regex` are set

5. **`ScriptAnalysisService` tests**:
   - Happy path: 3-column output (`LINE\tCHAR\tSCORE`) → violations use `rule.violationMessage ?? rule.description` as comment
   - Happy path: 4-column output (`LINE\tCHAR\tSCORE\tCOMMENT`) → violations use script-provided comment
   - Mixed 3 and 4 column lines in same output → each violation gets correct comment source
   - No violations: script outputs empty stdout → empty violations array
   - Script error: non-zero exit code → `RuleError`
   - **Strict parsing errors** (each should throw `RuleError`, not return partial results):
     - Wrong column count (1, 2, or 5+ columns)
     - Non-integer line number
     - Non-integer character position
     - Non-integer score
     - Score out of range (0, 11, -1)
   - Post-filtering: script reports violations on lines 10, 15, 20; only line 15 is a changed line → only line 15 violation survives
   - `newCodeLinesOnly: true` filtering: verify only `changeKind == .added` lines pass; `.changed`, `.removed`, `.unchanged` are excluded
   - `newCodeLinesOnly: false` filtering: verify all lines with `changeKind != .unchanged` pass
   - Script not found / not executable: descriptive error

6. **`AnalysisMethod.script` codable tests**: Round-trip encoding/decoding.

7. **Integration: `AnalysisService` dispatch tests**: Verify script tasks route to `ScriptAnalysisService`.

## - [ ] Phase 6: Validation

**Skills to read**: `/swift-testing`

1. Run full test suite: `cd PRRadarLibrary && swift test`
2. Run build: `cd PRRadarLibrary && swift build`
3. Create a test script in the test repo (`/Users/bill/Developer/personal/PRRadar-TestRepo`) and a rule that references it
4. Run the pipeline end-to-end: `swift run PRRadarMacCLI analyze 1 --config test-repo --mode script`
5. Verify script violations appear in the output and result JSON
6. Verify violations on untouched lines are filtered out
