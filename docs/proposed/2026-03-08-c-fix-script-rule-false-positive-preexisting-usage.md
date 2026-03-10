# Fix: Script Rule False Positive on Pre-existing Service Locator Usage

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `pr-radar-debug` | Debugging context for reproducing issues via CLI |
| `pr-radar-add-rule` | Context for rule structure and evaluation modes |
| `swift-testing` | Test conventions for unit tests |

## Background

The `service-locator-usage` script rule produces false positives when existing (unchanged) usage of a service locator falls **inside** the focus area range rather than outside it.

### The Problem

Discovered on PR #18982, file `JeppServiceRequest.m`:
- **Line 81** (unchanged): `[FFSLObjC.shared.jeppesen getSiteKey:!forLinkedData]` — pre-existing usage
- **Line 84** (new): `[FFSLObjC.shared.jeppesen getSiteKey:forLinkedData]` — flagged as violation

The rule's intent is to only flag service locator usage in files that **did not already use** that locator. But the script incorrectly concluded `FFSLObjC` was new to the file.

### Root Cause

The script (`check-service-locator-usage.sh`) checks for pre-existing locator references only **outside** the focus area range (before `START_LINE` and after `END_LINE`). For this file:

- Focus area: lines **12–104** (nearly the entire 116-line file)
- Existing usage at line 81 falls **inside** the range
- Lines 1–11 and 105–116 have no `FFSLObjC.` references
- Script concludes: "locator is new to file" → flags line 84

The script can't distinguish changed lines from unchanged context lines within the range — it only receives `FILE`, `START_LINE`, and `END_LINE`.

### Why Post-filtering Doesn't Help

`ScriptAnalysisService.swift` already post-filters script output to only keep violations on changed lines. This correctly drops violations on unchanged lines. But in this case, line 84 IS a changed line — the false positive comes from the script's incorrect "is this locator new?" decision, not from the line-level filtering.

## Proposed Fix

Pass changed line numbers from `ScriptAnalysisService` to the script as a 4th argument (comma-separated). This lets the script check if the locator appears on any **unchanged** line, which is the correct pre-existing check.

### Changes

**1. `ScriptAnalysisService.swift`** — Compute changed line numbers (already available from `hunks`) and pass as 4th process argument.

**2. `check-service-locator-usage.sh`** — Accept optional 4th arg. When present:
- For each locator, grep the entire file for references
- If any reference is on a line NOT in the changed-lines set, the locator is pre-existing → skip
- In the violation output loop, also skip lines not in the changed set (redundant with post-filter but keeps script output clean)
- When 4th arg is absent, fall back to the existing outside-range check for backward compatibility

### Why This Approach

- **Minimal blast radius**: Only the service-locator script needs the info; other scripts still get 3 args
- **Backward compatible**: The 4th arg is optional; the script falls back to current behavior without it
- **Correct**: Changed lines from the diff hunks are the source of truth for what's new vs pre-existing
- **No git dependency in script**: The script doesn't need to run `git diff` or know the base branch

## - [ ] Phase 1: Pass changed lines from ScriptAnalysisService

**Skills to read**: `pr-radar-debug`

- In `ScriptAnalysisService.swift`, compute the set of changed line numbers from `hunks` (using `relevantLineNumbers`)
- Pass as comma-separated 4th argument to the script process
- Update the command log entry to include the new argument

**File**: `PRRadarLibrary/Sources/services/PRRadarCLIService/ScriptAnalysisService.swift`

## - [ ] Phase 2: Update check-service-locator-usage.sh

**Skills to read**: `pr-radar-add-rule`

- Accept `CHANGED_LINES` as optional 4th arg
- Replace the "outside count" block with changed-line-aware logic when arg is present
- Keep existing fallback for when arg is absent
- In the violation loop, skip non-changed lines when arg is present

**File**: `/Users/bill/Desktop/pr-radar-experimental-rules/apis-ffm/check-service-locator-usage.sh`

## - [ ] Phase 3: Validation

**Skills to read**: `swift-testing`, `pr-radar-debug`

- `swift build` to verify compilation
- Add unit test for `ScriptAnalysisService` verifying the 4th argument is passed
- Clear cached evaluation for PR 18982: `rm -rf ~/Desktop/code-reviews/18982/analysis/*/evaluate/*service-locator*JeppServiceRequest*`
- Re-run: `swift run PRRadarMacCLI prepare 18982 --config ios --rules-path-name experiment --quiet`
- Re-run: `swift run PRRadarMacCLI analyze 18982 --config ios --mode script`
- Expected: 0 violations for `JeppServiceRequest.m` `service-locator-usage`
