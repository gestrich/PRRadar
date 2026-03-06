# Flat Task-Level Caching

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules for placement and dependency guidance |
| `swift-testing` | Test style guide for new/modified tests |
| `pr-radar-verify-work` | Verify changes by running CLI against the test repo |

## Background

PRRadar supports multiple rule paths per configuration (added in the multiple-rule-paths spec). However, running the pipeline with different rule directories for the same PR and commit **overwrites** previous results, because `TaskCreatorService` deletes all existing task files before writing new ones (lines 98-104).

### Root cause

The `prepare` phase does a clean-before-write: it deletes all `data-*.json` files in the tasks directory, then writes the new tasks. This means running with rulesDir=pathA then rulesDir=pathB destroys pathA's tasks. PathA's evaluate results remain on disk but are orphaned — no task references them, so reports ignore them.

### Design principle

- **Prepare** is scoped to a rules dir — it creates tasks for the selected rules path only
- **Analyze** evaluates only the tasks from the current prepare run (not all tasks on disk). Cache handles any that were already evaluated.
- **Report** aggregates all evaluations on disk across all rule dirs

This means clicking "swift-rules" prepares + evaluates swift-rules. Clicking "security-rules" prepares + evaluates security-rules. The report combines both.

### Cost analysis

With the additive approach, running pathB after pathA:
- PathA's tasks remain in the tasks directory
- Analyze only evaluates pathB's tasks (passed from prepare), not pathA's
- If pathB shares a rule with pathA and the file hasn't changed, cache hits that evaluation
- Focus areas depend on the diff (not rules), so regenerating them on the second run is wasted — skip when they already exist

| Stage | Today (destructive) | Additive | Difference |
|-------|---|---|---|
| Focus areas (Haiku) | Paid each run | Skip if already exist | **Saves money** |
| Regex/script eval | Only latest dir | Only current dir's tasks | Same |
| AI eval (Sonnet) | Only latest dir | Only current dir's tasks (cache hits shared rules) | Same or less |
| Report coverage | Last dir only | All dirs combined | Better |

### Key files

- `TaskCreatorService.swift` — cleans and writes task files (lines 98-104 do the destructive delete)
- `PrepareUseCase.swift` — writes focus areas, rules, tasks
- `AnalyzeUseCase.swift` — orchestrates evaluation, reads tasks from prepare
- `AnalysisCacheService.swift` — task-level cache partitioning (already blob-hash based)
- `ReportUseCase.swift` — generates reports from evaluate results
- `RunPipelineUseCase.swift` — full pipeline orchestration
- `RuleRequest.swift` — task model, `taskId` = `<ruleName>_<focusId>`

## Phases

## - [ ] Phase 1: Make TaskCreatorService additive and handle task ID collisions

**Skills to read**: `swift-app-architecture:swift-architecture`

Two changes:

**a) Remove destructive clean-before-write** (lines 98-104 in `TaskCreatorService`). New tasks write alongside existing ones. If a task file with the same `taskId` already exists, overwrite just that file (rule content may have changed).

**b) Handle task ID collisions.** Task IDs are currently `<ruleName>_<focusId>`. If two rule directories contain a rule with the same name (e.g., both have `no-force-unwrap.yml`), their task IDs collide and one overwrites the other. Fix by incorporating a distinguishing component into the task ID — either the rule blob hash or a short hash of the rule file path. This ensures tasks from different rule files are always distinct, even if they share a name.

Verify: existing cache lookups still work after the task ID format change (cache matches on blob hashes, not task IDs, so this should be fine — but the file names in the evaluate directory use task IDs, so prior cached results will miss. Acceptable since no backwards compatibility is required).

## - [ ] Phase 2: Skip focus area regeneration when already present

**Skills to read**: `swift-app-architecture:swift-architecture`

Focus areas depend on the diff, not on which rules are loaded. In `PrepareUseCase`, check if the focus-areas subdirectory already contains output files for the current commit. If so, skip the Haiku AI call and load existing focus areas from disk.

This saves real money on consecutive runs with different rule directories (or re-runs of the same directory).

## - [ ] Phase 3: Feed prepare's tasks directly to analyze in the pipeline

**Skills to read**: `swift-app-architecture:swift-architecture`

Currently `AnalyzeUseCase.executeFullRun()` loads all tasks from the prepare directory on disk (line 34-36). This means it evaluates every task from every prior rules dir, not just the ones from the current run.

Change the pipeline flow so analyze receives tasks from prepare's output rather than reading from disk:

- `RunPipelineUseCase` already gets `PrepareOutput` (which contains the task list). Pass those tasks to `AnalyzeUseCase` instead of having analyze re-read from disk.
- `AnalyzeUseCase` gains an overload or parameter that accepts tasks directly. The existing disk-based path can remain for standalone CLI usage (`analyze` command without a preceding `prepare`).
- When analyze receives tasks directly, it still uses `AnalysisCacheService` to check for cached evaluations — so shared rules between dirs get cache hits.

This ensures:
- Pipeline (MacApp button / `RunPipelineUseCase`): evaluates only this run's tasks
- Standalone `analyze` CLI command: evaluates all tasks on disk (useful for "evaluate everything" scenarios)

## - [ ] Phase 4: Make rules output additive

**Skills to read**: `swift-app-architecture:swift-architecture`

Currently `all-rules.json` is overwritten each run. Determine whether any downstream code reads `all-rules.json`. If nothing depends on it beyond informational display, this is low priority. If it's used, either:
- Write per-rules-dir files (e.g., `rules-<slug>.json`)
- Or merge into a combined file

## - [ ] Phase 5: Verify report and status work with merged results

**Skills to read**: `swift-app-architecture:swift-architecture`

- `ReportUseCase` reads all evaluations from the evaluate directory — should naturally include results from all rule dirs
- `status` command should show total tasks across all rule dirs
- Verify `summary.json` stats reflect the full merged set

## - [ ] Phase 6: Validation

**Skills to read**: `swift-testing`, `pr-radar-verify-work`

1. **Unit tests**:
   - `TaskCreatorService`: Writing tasks from dirB preserves dirA's task files
   - Task ID uniqueness: Same-named rules from different directories produce different task IDs
   - Focus area skip: Existing focus areas are loaded from disk instead of regenerated
   - Analyze with direct task list: only evaluates given tasks, not all on disk

2. **Integration test via CLI**:
   - Run full pipeline with `--rules-path-name pathA` on test repo PR
   - Run full pipeline with `--rules-path-name pathB` on the same PR
   - Verify pathA's evaluations still exist on disk
   - Run `report` — verify findings from both rule sets appear
   - Re-run pathA — verify all tasks are cached

3. **Build**: `swift build` and `swift test` pass
