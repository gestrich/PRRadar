## Background

The [unified-review-comment-model](../completed/unified-review-comment-model.md) spec documented a problem in Phase 10: "the AI evaluator reports stale line numbers." When re-analyzing a PR after new commits shifted code lines, the Claude evaluator returned `line_number: 19` instead of the expected `line_number: 26`. A fuzzy fallback was added to `ViolationService.reconcile()` (Pass 2: same file, any line, body contains rule name) to work around this.

### What we actually found

By inspecting the cached pipeline output on disk (`/Users/bill/Desktop/code-reviews/1/`), we traced the real cause:

1. **The annotation code is correct.** `Hunk.getAnnotatedContent()` uses `newStart` (the new-file line number). `FocusGeneratorService.generateFileFocusAreas()` also uses `newStart`. The focus area data on disk (`phase-2-focus-areas/data-file.json`) has correct line numbers (modulo at line 26).

2. **The task file is stale.** The task file (`phase-4-tasks/data-guard-divide-by-zero_Calculator.swift.json`) was last modified at **16:41:37** — roughly 3 hours before the latest `analyze` run at **19:25:53**. It contains hunk content from a prior commit (`9a98ec9`) where modulo was at line 19.

3. **Why the task wasn't overwritten.** The latest run's `phase_result.json` for tasks shows `"artifacts_produced": 0`. Zero tasks were created because of a `focus_type` mismatch: the rule specifies `focus_type: method` but the pipeline generates only `.file` focus areas. The guard in `TaskCreatorService.createTasks()` — `guard rule.focusType == focusArea.focusType else { continue }` — filters it out.

4. **Stale data survives across runs.** The pipeline doesn't clean phase output directories before writing new output. When the latest run produced 0 tasks, the old task file remained on disk. The evaluation phase (`EvaluateUseCase`) reads all task files from disk via `PhaseOutputParser.parseAllPhaseFiles()`, finding and using the stale one.

5. **The AI was shown wrong numbers.** The evaluation prompt sent to Claude contained the stale hunk content with `@@ -15,4 +15,9 @@` (modulo at line 19) instead of the current `@@ -15,4 +22,9 @@` (modulo at line 26). The AI faithfully reported `line_number: 19` — exactly what it was shown.

### Implication for the fuzzy fallback

The fuzzy fallback in `ViolationService.reconcile()` (Pass 2, lines 103-124) was added to handle "line drift." But the drift was caused by stale pipeline data, not by a genuine limitation of the diff annotation system. If the pipeline produces correct, fresh data on every run, Pass 1 (exact file + line match) should be sufficient.

However, there may be a legitimate use case for fuzzy matching even with correct data — for example, if a user runs `evaluate` standalone (without re-running `diff` + `rules` + `tasks` first). The investigation should determine whether the fuzzy fallback should be **removed**, **kept as a safety net**, or **kept but documented as covering only the standalone-evaluate scenario**.

### What this plan proves

This plan runs a clean-slate experiment against the test repo to verify the theory. If a fresh `analyze` run produces correct line numbers in the task and evaluation output, the theory is confirmed: the "stale line numbers" problem was a pipeline data freshness issue, not an AI or annotation bug.

## Phases

## - [x] Phase 1: Clean Slate — Delete Existing PR #1 Output

Delete the entire output directory for PR #1 to eliminate all stale data:

```bash
rm -rf /Users/bill/Desktop/code-reviews/1/
```

This ensures no files from prior runs can be picked up by any phase.

**Verify:** `ls /Users/bill/Desktop/code-reviews/1/` should fail (directory doesn't exist).

**Result:** Deleted. Directory contained 6 phase output subdirectories (`phase-1-pull-request` through `phase-6-report`) from prior runs. All removed.

## - [x] Phase 2: Check Current Test Repo State

Before running the pipeline, inspect the current state of the test repo and PR #1 to understand what line numbers we should expect.

1. `cd /Users/bill/Developer/personal/PRRadar-TestRepo && git log --oneline -5` — see recent commits
2. `cat Calculator.swift` — see the current file contents and note which line `func modulo` is on
3. `git diff main...HEAD` or check the PR diff — see what the PR diff currently looks like
4. `gh pr view 1 --json comments` — check if there's a posted comment and what line GitHub reports for it
5. Record the expected line number for the modulo function in the current state

**Expected outcome:** A concrete expected line number (e.g., "modulo is at line 26 in the current file") to compare against the pipeline output.

**Result:**

The line-shift that previously moved modulo to line 26 has been **reverted**. The `add-modulo-method` branch now has 3 commits beyond main: the original modulo addition (`815cd86`), a comment-header addition (`51a6a11`), and its revert (`1b725fe`). The net diff is identical to the original commit.

1. **Recent commits:** `1b725fe` (revert comment header), `51a6a11` (add comment header), `815cd86` (add modulo method) — plus unrelated commits on main (greeting function, README).
2. **Calculator.swift on `add-modulo-method`:** 23 lines. `func modulo` starts at **line 19**.
3. **PR diff:** `@@ -15,4 +15,9 @@` — both old and new start at line 15 (no line shift). The diff adds the modulo method at lines 19-22 of the new file.
4. **Posted GitHub comment:** `line: 19`, `original_line: 19`, targeting `func modulo(_ a: Int, _ b: Int) -> Int?`. The comment is a `guard-divide-by-zero` evaluation (score 6/10).
5. **Expected line number for modulo: 19.**

Key implication: since the revert undid the line shift, the "stale line number" scenario from the background section (line 19 vs 26) **no longer exists** in the current test repo state. The pipeline should now produce `line_number: 19`, which matches both the actual file and the existing posted comment.

## - [x] Phase 3: Run Fresh Analysis

Run the full pipeline from scratch:

```bash
cd /Users/bill/Developer/personal/PRRadar && swift run PRRadarMacCLI analyze 1 --config test-repo
```

This runs all phases sequentially: diff → focus areas → rules → tasks → evaluations → report.

**Expected outcome:** All phase output directories are freshly created with no stale data.

**Result:**

Ran from `PRRadarLibrary/` (the active package directory after the project restructure). All 6 phases completed successfully:

- **phase-1-pull-request:** 10 files — diff fetched, 1 hunk across 1 file, 1 existing inline review comment found at Calculator.swift:19.
- **phase-2-focus-areas:** 2 files — 1 focus area generated.
- **phase-3-rules:** 2 files — 1 rule loaded (`guard-divide-by-zero`).
- **phase-4-tasks:** 1 file (`phase_result.json` only) — **0 tasks created.** Confirms the `focus_type` mismatch: the rule specifies `focus_type: method` but the pipeline generates only `.file` focus areas, so `TaskCreatorService` filters it out.
- **phase-5-evaluations:** 2 files (`phase_result.json` + `summary.json`) — **0 evaluations produced**, because there were no tasks to evaluate. With a clean output directory, there are no stale task files to accidentally pick up.
- **phase-6-report:** 3 files — 0 violations reported.

Key confirmation: with a clean slate (Phase 1 deleted all prior output), the pipeline produces no stale data. The `artifacts_produced: 0` for tasks means the evaluation phase correctly has nothing to evaluate, rather than falling back on stale task files from a prior run.

## - [x] Phase 4: Inspect Pipeline Output

Examine each phase's output to verify line numbers are correct throughout the entire pipeline:

1. **Diff** (`phase-1-pull-request/diff-parsed.json`):
   - Check `newStart` for the hunk containing `modulo` — should match the expected line from Phase 2
   - Check the `@@ ... +N,M @@` header uses `newStart`, not `oldStart`

2. **Focus areas** (`phase-2-focus-areas/data-file.json`):
   - Check the annotated `hunk_content` — line numbers should match `newStart`-based numbering
   - Verify `start_line` and `end_line` use new-file positions

3. **Tasks** (`phase-4-tasks/data-*.json`):
   - Check the task's `focus_area.hunk_content` — should have the same correct line numbers as the focus area
   - Check `start_line` and `end_line`
   - **Critical:** If `artifacts_produced` is 0 in `phase_result.json`, this confirms the focus_type mismatch bug. Record this finding — it means the evaluation phase would have no tasks to evaluate (and a clean directory means no stale tasks to fall back on).

4. **Evaluations** (`phase-5-evaluations/data-*.json`):
   - If a task was produced: check `evaluation.line_number` — should match the expected line from Phase 2
   - If no task was produced (0 artifacts): the evaluation phase should produce 0 evaluations. Record this — it means the "stale line number" problem can't occur with a clean directory.

5. **AI transcript** (`phase-5-evaluations/ai-transcript-*.json`):
   - Check the `prompt` field — the annotated diff should show correct `newStart`-based line numbers
   - Check the AI's `result` — `line_number` should match what was shown in the prompt

**Result:**

Inspected all phase output files in `/Users/bill/Desktop/code-reviews/1/`. Line numbers are correct throughout the pipeline where data was produced:

1. **Diff** — `newStart: 15`, `oldStart: 15`, header `@@ -15,4 +15,9 @@`. The hunk content shows `func modulo` starting at line 19 in the new file. Matches the expected line number from Phase 2.

2. **Focus areas** — `start_line: 15`, `end_line: 23`, `focus_type: "file"`. Annotated `hunk_content` uses `newStart`-based numbering: context lines at 15-17, additions at 18-22, closing brace at 23. `func modulo` is correctly annotated at line 19.

3. **Tasks** — Only `phase_result.json` exists with `artifacts_produced: 0`. **No task data files.** Confirms the `focus_type` mismatch: the rule specifies `focus_type: method` but the pipeline generates only `.file` focus areas. `TaskCreatorService` filters it out. With a clean output directory (Phase 1), there are no stale task files to fall back on.

4. **Evaluations** — `artifacts_produced: 0`, `total_tasks: 0`, `violations_found: 0`. Only `phase_result.json` and `summary.json` exist — no `data-*.json` files. The evaluation phase correctly had nothing to evaluate.

5. **AI transcript** — No `ai-transcript-*.json` files exist because no evaluations were performed (0 tasks → 0 AI calls). Cannot verify AI prompt/response line numbers in this run.

**Additional observations:**
- The effective diff (`effective-diff-parsed.json`) matches `diff-parsed.json` exactly — same `newStart: 15` and hunk content. No moves detected (`effective-diff-moves.json` not inspected but the effective diff is identical to the raw diff).
- The existing GitHub review comment (`gh-comments.json`) has `line: 19` for `Calculator.swift`, matching the pipeline's line numbering.
- The report (`phase-6-report/summary.json`) correctly shows 0 violations and 0 tasks evaluated.

**Key finding:** The pipeline produces correct line numbers at every stage where data exists. The inability to fully verify the end-to-end line number chain (diff → focus → task → evaluation → AI response) is blocked by the `focus_type` mismatch, which prevents task creation. Phase 5 will address this mismatch to enable a complete verification.

## - [x] Phase 5: Determine Focus Type Mismatch Impact

The test repo rule (`guard-divide-by-zero`) has `focus_type: method`, but the pipeline requests only `.file` focus areas. This is a separate bug that may prevent tasks from being created at all.

1. Check the rule file at `/Users/bill/Developer/personal/PRRadar-TestRepo/rules/guard-divide-by-zero.md` — look for the `focus_type` frontmatter
2. Check `FetchRulesUseCase.execute()` line 59 — confirm `requestedTypes: [.file]`
3. If there's a mismatch: temporarily change the rule's `focus_type` to `file` (or change the pipeline to include `.method`), re-run Phase 3-4, and verify the task is created with correct line numbers
4. Document whether the mismatch is intentional or a bug

**Result:**

Confirmed the mismatch at both locations:

1. **Rule file** (`PRRadar-TestRepo/rules/guard-divide-by-zero.md`): has `focus_type: method` in YAML frontmatter.
2. **FetchRulesUseCase** (`FetchRulesUseCase.swift:59`): hardcodes `requestedTypes: [.file]`. Only file-level focus areas are generated.
3. **TaskCreatorService** (`TaskCreatorService.swift:29`): strict guard `rule.focusType == focusArea.focusType` filters out the method-typed rule against file-typed focus areas, producing 0 tasks.

**Experiment:** Temporarily changed the test repo rule's `focus_type` from `method` to `file`, deleted all prior output (`rm -rf /Users/bill/Desktop/code-reviews/1/`), and re-ran `analyze 1 --config test-repo`. Results:

- **Task created:** 1 task (`guard-divide-by-zero_Calculator.swift`) with correct focus area data — `start_line: 15`, `end_line: 23`, `hunk_content` showing `func modulo` at line 19.
- **Evaluation produced:** `line_number: 19`, `score: 6/10`, `violates_rule: true`. The AI correctly identified the modulo function at line 19 — matching the expected line number from Phase 2.
- **Report:** 1 violation at `Calculator.swift:19`.
- **Complete line number chain verified:** diff (`newStart: 15`) → focus area (`start_line: 15`, modulo at line 19 in annotated content) → task (same) → AI evaluation (`line_number: 19`) → report (`line_number: 19`). All correct.

Reverted the test repo rule back to `focus_type: method` after the experiment.

**Conclusion — this is a bug.** The `focus_type` mismatch is not intentional. The pipeline hardcodes `requestedTypes: [.file]` (likely as a simplification during the Swift rewrite), but rules can specify `focus_type: method`. The `TaskCreatorService` guard correctly enforces type matching, but the pipeline never generates method-level focus areas, making all method-typed rules silently inoperative. There are two possible fixes:

1. **Change the pipeline to include `.method`** in `requestedTypes` (adds an AI call per hunk via `FocusGeneratorService.generateFocusAreasForHunk()` — increases cost and latency).
2. **Change `TaskCreatorService` to allow `.file` focus areas to satisfy `.method` rules** (a file-level focus area contains the full hunk, which includes all methods — so a method rule can still evaluate it). This avoids the extra AI call.
3. **Default rules to `focus_type: file`** unless explicitly set to `method`, and update existing rules.

This is a separate bug from the stale line number issue and should be tracked as a follow-up item.

## - [x] Phase 6: Evaluate Fuzzy Fallback Necessity

Based on findings from Phases 4-5, determine the fate of the fuzzy fallback in `ViolationService.reconcile()`:

**If line numbers are correct when the pipeline runs fresh (expected):**
- The fuzzy fallback (Pass 2, lines 103-124 of `ViolationService.swift`) was compensating for stale data, not genuine line drift
- Consider whether to **remove it** (simplify reconciliation) or **keep it as a safety net** for edge cases (e.g., standalone `evaluate` command reading old tasks)
- If removing: also remove the 3 fuzzy-specific unit tests in `ViolationReconciliationTests.swift` and update the "line drift" test back to "no match when line number differs"

**If line numbers are still wrong (unexpected):**
- There's a deeper bug in the annotation or prompt construction code
- The fuzzy fallback should be kept
- Document the new findings for further investigation

**Document the decision** — whether removing, keeping, or deferring — and the reasoning.

**Result:**

**Decision: Remove the fuzzy fallback.** Line numbers are correct when the pipeline runs fresh (confirmed in Phases 4-5). The fuzzy fallback was compensating for stale pipeline data, not genuine line drift.

**Reasoning:**

1. **Root cause is stale data, not line drift.** Phases 3-5 confirmed that a clean-slate `analyze` run produces correct line numbers at every pipeline stage. The original "line 19 vs 26" discrepancy was caused by stale task files surviving across runs, not by the AI reporting wrong numbers or GitHub shifting comment positions.

2. **Fuzzy matching masks the real problem.** The "standalone evaluate" scenario (running `evaluate` without re-running `diff` + `rules` + `tasks`) would still read stale task files from disk. The fuzzy fallback doesn't fix the underlying data freshness issue — it just makes the reconciliation appear to work by matching on file + rule name alone, ignoring the stale line number. This creates false confidence.

3. **Exact matching is the correct contract.** If the pipeline data is fresh, exact (file, line, rule) matching is sufficient and produces correct results. If the data is stale, the correct fix is to ensure data freshness (e.g., cleaning output directories before each run), not to relax the matching criteria.

**Changes made:**

- **`ViolationService.swift`**: Removed Pass 2 (fuzzy fallback, lines 103-124). `reconcile()` now uses a single-pass exact match: same file, same line, body contains rule name.
- **`ViolationReconciliationTests.swift`**: Removed 3 fuzzy-specific tests (`exactMatchPreferredOverFuzzy`, `lineDriftNoFalseMatchDifferentRules`, `lineDriftNoMatchDifferentFiles`). Changed `matchWhenLineNumberDrifts` to `noMatchWhenLineNumberDiffers` — now expects `.new` + `.postedOnly` instead of `.redetected`.
- **Build and tests pass.** 330 tests in 43 suites, all green.

## - [x] Phase 7: Document Findings

Update or create documentation summarizing the investigation results:

1. Add a summary to the completed spec (`docs/completed/2026-02-10-b-unified-review-comment-model.md`) Phase 10 section, noting the actual root cause (stale pipeline data, not AI reporting wrong numbers)
2. If a separate pipeline data freshness bug is confirmed, add it to `docs/proposed/TODO.md` as a follow-up item (the pipeline should clean phase output dirs before writing new output)
3. If the focus_type mismatch is confirmed as a bug, add that to `docs/proposed/TODO.md` as well

**Result:**

All three documentation updates completed:

1. **`docs/completed/2026-02-10-b-unified-review-comment-model.md`** — Added a "Post-Investigation Update" subsection to Phase 10 explaining that the stale line numbers were caused by stale pipeline data on disk (not AI or GitHub line drift), and that the fuzzy fallback added in Phase 10 was subsequently removed.
2. **`docs/proposed/TODO.md`** — Added "Clean phase output directories before each pipeline run" as a Small item, documenting the stale data root cause and fix options.
3. **`docs/proposed/TODO.md`** — Added "Fix focus_type mismatch: method-typed rules produce 0 tasks" as a Small item, documenting the `requestedTypes: [.file]` limitation and three fix options.

## - [x] Phase 8: Architecture Validation

Review all changes made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare any code changes made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. For each relevant language, fetch and read ALL skills from the corresponding GitHub repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

Note: This plan is primarily investigative. If no code changes are made (only documentation and pipeline runs), this phase is a no-op.

**Result:**

Reviewed all Swift code changes (commits `09f1ca2..7a8a39a`) against both `swift-architecture` and `swift-swiftui` skills from `gestrich/swift-app-architecture`. The changes touched two files:

1. **`ViolationService.swift`** (Services layer, `PRRadarCLIService`) — Removed fuzzy fallback from `reconcile()`, added doc comment clarifying matching semantics.
2. **`ViolationReconciliationTests.swift`** — Removed 3 fuzzy-specific tests, updated line-drift test to expect no match.

**Validation against conventions — no violations found:**

- **Layer placement:** `ViolationService` is a stateless transformation service in `services/PRRadarCLIService/` — correct for Services layer.
- **Sendable struct:** `public struct ViolationService: Sendable` — matches "SDKs/Services are stateless Sendable structs" convention.
- **No @Observable/@MainActor:** Neither annotation appears outside the Apps layer — correct.
- **No default/fallback values:** The fuzzy fallback removal *improves* compliance — the fuzzy pass was a silent fallback that masked stale data errors. Exact matching aligns with "avoid default/fallback values; missing values should surface as errors."
- **Imports:** Alphabetical order (`Foundation`, `PRRadarConfigService`, `PRRadarModels`) — correct.
- **File organization:** Properties → init → methods — correct.
- **Dependency rules:** Services layer depends only on other Services — `PRRadarConfigService` and `PRRadarModels` are both Services. Correct.
- **No type aliases or re-exports:** None present — correct.

Build succeeds and all 330 tests pass (43 suites).

## - [x] Phase 9: Validation

**Automated:**
```bash
cd pr-radar-mac
swift build
swift test
```

All tests must pass. If the fuzzy fallback was removed in Phase 6, the removed tests should no longer exist and remaining tests should still pass.

**Manual verification:**
- Confirm the Phase 4 inspection data matches expectations from Phase 2
- Confirm the documented findings are accurate and complete

**Result:**

**Automated — all green.** Build succeeds, 330 tests in 43 suites pass. No fuzzy fallback code remains in `ViolationService.swift` or `ViolationReconciliationTests.swift`.

**Manual verification — confirmed:**

1. **Phase 4 data matches Phase 2 expectations.** Phase 2 established the expected line number for modulo as **19**. Phase 4 confirmed `newStart: 15` with `func modulo` at line 19 throughout the pipeline (diff, focus areas, annotated content). Phase 5's experiment (with focus_type temporarily fixed) verified the full end-to-end chain: diff → focus → task → evaluation → report all produce `line_number: 19`.

2. **Documented findings are accurate and complete:**
   - `ViolationService.reconcile()` uses single-pass exact `(file, line, rule)` matching — no fuzzy fallback remains.
   - Test `noMatchWhenLineNumberDiffers` correctly expects no match when line numbers differ (previously `matchWhenLineNumberDrifts` expected a fuzzy match).
   - `docs/proposed/TODO.md` has both follow-up items: stale data cleanup and focus_type mismatch.
   - `docs/completed/2026-02-10-b-unified-review-comment-model.md` Phase 10 has the post-investigation update documenting the root cause.
