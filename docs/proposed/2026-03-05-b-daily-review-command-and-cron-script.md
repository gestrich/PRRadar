## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules — placement of new command, use case, and threading of options through layers |
| `python-architecture:cli-architecture` | CLI structure patterns — though this is Swift CLI, the dispatcher/command pattern principles apply |

## Background

PRRadar already has a `run-all` CLI command that runs the full pipeline on all PRs since a given date. However it lacks:

1. **Analysis mode support** (`--mode regex/script/ai/all`) — `AnalyzeCommand` supports modes but `RunPipelineUseCase` hardcodes `PRReviewRequest` without one
2. **Lookback-hours convenience option** — `run-all` requires a specific `--since YYYY-MM-DD` date; a daily cron needs "last N hours" semantics without computing the date externally
3. **A bash wrapper script** for the cron job that supplies Bill's personal repo/config params and fires a macOS notification when complete

The bash script will live in the repo (e.g. `scripts/daily-review.sh`) but be git-ignored since it contains personal config values. It will be set up as a 5:30 AM `launchd` or `cron` job and use `osascript` to post a macOS notification on completion.

## Phases

## - [x] Phase 1: Add `--mode` threading through `RunPipelineUseCase` and `RunAllUseCase`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Added `analysisMode` with default `.all` to preserve backwards compatibility; threaded through all three files with no new files created

**Skills to read**: `swift-app-architecture:swift-architecture`

`RunPipelineUseCase.execute()` builds a `PRReviewRequest` on line 99 without an `analysisMode`. The mode needs to flow from the command down through the call chain.

Changes:
- **`RunPipelineUseCase`**: Add `analysisMode: AnalysisMode = .all` param to `execute()`. Pass it into the `PRReviewRequest` constructed for `AnalyzeUseCase`.
- **`RunAllUseCase`**: Add `analysisMode: AnalysisMode = .all` param to `execute()`. Pass it through to `RunPipelineUseCase.execute()`.
- **`RunAllCommand`**: Add `@Option var mode: AnalysisMode = .all` (already has `ExpressibleByArgument` extension from `AnalyzeCommand`). Pass it to `useCase.execute()`.

No new files. Only the three existing files change.

## - [x] Phase 2: Add `--lookback-hours` to `RunAllCommand`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Made `--since` optional, added `--lookback-hours: Int?`, computed cutoff date inline in `run()`, `ValidationError` thrown when neither flag is provided for clean ArgumentParser error output

**Skills to read**: `swift-app-architecture:swift-architecture`

`RunAllCommand` already covers the same ground as a hypothetical `DailyReviewCommand` — it fetches PRs since a date, runs the full pipeline, and supports `--config`/`--comment`/`--state`. Rather than create a duplicate command, extend `RunAllCommand` directly.

Changes to `RunAllCommand.swift`:
- Add `@Option(name: .long) var lookbackHours: Int?` — when provided, computes `since` as `ISO8601(Date.now - lookbackHours * 3600)` (YYYY-MM-DD format). Make `--since` optional (currently required `@Option`); validation fails if neither `--since` nor `--lookback-hours` is provided.
- The bash script then calls `run-all` with `--lookback-hours 24` instead of computing dates externally.

After this phase the cron invocation looks like:
```
swift run PRRadarMacCLI run-all \
  --config your-config \
  --lookback-hours 24 \
  --mode all \
  --state open \
  --comment
```

## - [x] Phase 3: Create bash wrapper script and update `.gitignore`

**Skills used**: none
**Principles applied**: Script uses `--mode regex` only; `daily-review.sh` git-ignored to protect personal config values

Create `scripts/daily-review.sh` with this structure:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$REPO_ROOT/PRRadarLibrary/.build/release/PRRadarMacCLI"

# Build if binary is missing or stale
if [ ! -f "$CLI" ] || [ "$REPO_ROOT/PRRadarLibrary/Sources" -nt "$CLI" ]; then
  cd "$REPO_ROOT/PRRadarLibrary" && swift build -c release --quiet
fi

# Run the daily review
"$CLI" run-all \
  --config "your-config-name" \
  --lookback-hours 24 \
  --mode all \
  --state open \
  # --comment   # uncomment to post comments automatically

EXIT_CODE=$?

# macOS notification
if [ $EXIT_CODE -eq 0 ]; then
  osascript -e 'display notification "Daily PR review complete" with title "PRRadar" sound name "Glass"'
else
  osascript -e 'display notification "Daily PR review failed (exit '"$EXIT_CODE"')" with title "PRRadar" sound name "Basso"'
fi

exit $EXIT_CODE
```

Also add `scripts/daily-review.sh` to `.gitignore` so personal config values are never committed.

The script is intentionally simple — Bill fills in the real `--config` value (and optionally `--comment`) before first use.

## - [x] Phase 4: Document cron / launchd setup in a comment block in the script

**Skills used**: none
**Principles applied**: Both cron and launchd options documented; launchd plist template included inline so no separate file needed

Add a comment at the top of `daily-review.sh` explaining how to wire it up:

**Option A — cron** (simpler):
```
# Add to crontab with: crontab -e
# 30 5 * * * /path/to/repo/scripts/daily-review.sh >> /tmp/prradar-daily.log 2>&1
```

**Option B — launchd** (preferred on macOS, survives sleep/wake, runs even if machine was asleep at 5:30):
```
# Create ~/Library/LaunchAgents/com.prradar.daily-review.plist
# See comment in script for full plist template
```

Include a minimal `launchd` plist template in the comment (not as a separate file) so Bill can copy it directly. Use `StartCalendarInterval` with `Hour=5 Minute=30`.

## - [x] Phase 5: Validation

**Skills used**: none
**Principles applied**: Build clean, 658 tests passing, smoke test confirmed `--lookback-hours` and `--mode regex` work end-to-end with no AI calls

**Skills to read**: `swift-testing`

Automated:
```bash
cd PRRadarLibrary
swift build   # verifies all changed files compile
swift test    # regression — existing 431 tests should still pass
```

Manual smoke test:
```bash
swift run PRRadarMacCLI run-all --config test-repo --lookback-hours 720 --mode regex --state open
# Should list PRs, run regex analysis, print summary
```

Verify `--mode` flows through by running with `--mode regex` and confirming no AI calls are made (no cost logged).

Test notification manually:
```bash
osascript -e 'display notification "Daily PR review complete" with title "PRRadar" sound name "Glass"'
```

Success criteria:
- Build passes with no new warnings
- All existing tests pass
- `run-all --lookback-hours` works and `--since` remains usable (backwards-compatible)
- `daily-review.sh` is listed in `.gitignore`
