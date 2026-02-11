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

## - [ ] Phase 2: Check Current Test Repo State

Before running the pipeline, inspect the current state of the test repo and PR #1 to understand what line numbers we should expect.

1. `cd /Users/bill/Developer/personal/PRRadar-TestRepo && git log --oneline -5` — see recent commits
2. `cat Calculator.swift` — see the current file contents and note which line `func modulo` is on
3. `git diff main...HEAD` or check the PR diff — see what the PR diff currently looks like
4. `gh pr view 1 --json comments` — check if there's a posted comment and what line GitHub reports for it
5. Record the expected line number for the modulo function in the current state

**Expected outcome:** A concrete expected line number (e.g., "modulo is at line 26 in the current file") to compare against the pipeline output.

## - [ ] Phase 3: Run Fresh Analysis

Run the full pipeline from scratch:

```bash
cd /Users/bill/Developer/personal/PRRadar && swift run PRRadarMacCLI analyze 1 --config test-repo
```

This runs all phases sequentially: diff → focus areas → rules → tasks → evaluations → report.

**Expected outcome:** All phase output directories are freshly created with no stale data.

## - [ ] Phase 4: Inspect Pipeline Output

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

## - [ ] Phase 5: Determine Focus Type Mismatch Impact

The test repo rule (`guard-divide-by-zero`) has `focus_type: method`, but the pipeline requests only `.file` focus areas. This is a separate bug that may prevent tasks from being created at all.

1. Check the rule file at `/Users/bill/Developer/personal/PRRadar-TestRepo/rules/guard-divide-by-zero.md` — look for the `focus_type` frontmatter
2. Check `FetchRulesUseCase.execute()` line 59 — confirm `requestedTypes: [.file]`
3. If there's a mismatch: temporarily change the rule's `focus_type` to `file` (or change the pipeline to include `.method`), re-run Phase 3-4, and verify the task is created with correct line numbers
4. Document whether the mismatch is intentional or a bug

## - [ ] Phase 6: Evaluate Fuzzy Fallback Necessity

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

## - [ ] Phase 7: Document Findings

Update or create documentation summarizing the investigation results:

1. Add a summary to the completed spec (`docs/completed/unified-review-comment-model.md`) Phase 10 section, noting the actual root cause (stale pipeline data, not AI reporting wrong numbers)
2. If a separate pipeline data freshness bug is confirmed, add it to `docs/proposed/TODO.md` as a follow-up item (the pipeline should clean phase output dirs before writing new output)
3. If the focus_type mismatch is confirmed as a bug, add that to `docs/proposed/TODO.md` as well

## - [ ] Phase 8: Architecture Validation

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

## - [ ] Phase 9: Validation

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
