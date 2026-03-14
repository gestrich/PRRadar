---
name: pr-radar-debug
description: Debugging context for PRRadar with its configured repositories. Covers where rules, output, and settings live, and how to reproduce issues from the Mac app using CLI commands. Use this skill whenever debugging PRRadar behavior, investigating pipeline output, reproducing bug reports from the Mac app, or exploring rule evaluation results. Also use when Bill shares screenshots showing issues in the Mac app, or mentions code reviews, rule directories, output files, or PRRadar configs.
---

# PRRadar Debugging Guide

PRRadar has repository configurations available for debugging. Both the MacApp (GUI) and PRRadarMacCLI (CLI) share the same use cases and services, so any issue seen in the Mac app can be reproduced with CLI commands.

## Discovering Configurations

Settings are stored at:
```
~/Library/Application Support/PRRadar/settings.json
```

List configurations with:
```bash
cd PRRadarLibrary
swift run PRRadarMacCLI config list
```

Or read the JSON directly to see all config details (repo paths, rule paths, diff source, GitHub account, default base branch):
```bash
cat ~/Library/Application\ Support/PRRadar/settings.json
```

Each configuration includes:
- **Repo path** — local checkout of the repository
- **GitHub account** — owner/org on GitHub
- **Default base branch** — e.g. `develop` or `main`
- **Rule paths** — one or more named rule directories (relative to repo or absolute)

## Output Directory

Pipeline output location is defined in the configuration. Inspect the settings JSON to find the output directory. Output is organized as `<outputDir>/<PR_NUMBER>/` with subdirectories for each pipeline phase (metadata, diff, prepare, evaluate, report).

```bash
ls <outputDir>/<PR_NUMBER>/
```

## Reproducing Issues with CLI

The Mac app and CLI share the same use cases (in `PRReviewFeature`), so CLI commands reproduce the same behavior. Run from `PRRadarLibrary/`:

```bash
# Fetch diff
swift run PRRadarMacCLI diff <PR_NUMBER> --config <config-name>

# Generate focus areas and filter rules
swift run PRRadarMacCLI rules <PR_NUMBER> --config <config-name>

# Run evaluations
swift run PRRadarMacCLI evaluate <PR_NUMBER> --config <config-name>

# Generate report
swift run PRRadarMacCLI report <PR_NUMBER> --config <config-name>

# Full pipeline (diff + rules + evaluate + report)
swift run PRRadarMacCLI analyze <PR_NUMBER> --config <config-name>

# Check pipeline status
swift run PRRadarMacCLI status <PR_NUMBER> --config <config-name>
```

Use `--config <config-name>` to select the repository. Run `config list` to see available names. If `--config` is omitted, the default config is used.

## Logs

PRRadar writes structured JSON-line logs to `~/Library/Logs/PRRadar/prradar.log`. Both the Mac app and CLI write to this file. Use the `logs` command to read them:

```bash
# All log entries
swift run PRRadarMacCLI logs

# Most recent analysis run only
swift run PRRadarMacCLI logs --last-run

# Filter by date range
swift run PRRadarMacCLI logs --from 2026-03-14 --to 2026-03-14

# Filter by level (debug, info, warning, error)
swift run PRRadarMacCLI logs --level error

# JSON output for programmatic parsing
swift run PRRadarMacCLI logs --json
```

### Adding Logs for Debugging

When investigating issues, add temporary `Logger` calls at relevant code points to capture runtime state. Use `import Logging` and create a logger with `Logger(label: "PRRadar.<ComponentName>")`.

**For CLI debugging:** Add log statements, run the CLI command, then check output with `swift run PRRadarMacCLI logs --last-run`.

**For Mac app debugging:** Since the Mac app runs separately, tell Bill you are adding log statements to help troubleshoot, explain what information the logs will capture, then ask Bill to run the app and trigger the relevant action. After the run completes, read the logs with `swift run PRRadarMacCLI logs --last-run` to see what happened.

## Debugging Tips

- **Check pipeline phase output:** Look in `<outputDir>/<PR>/` for JSON artifacts from each phase.
- **Phase order:** METADATA -> DIFF -> PREPARE (focus areas, rules, tasks) -> EVALUATE -> REPORT
- **Phase result files:** Each phase writes a `phase_result.json` indicating success/failure.
- **Rule directories:** Rule paths are defined per-config in settings. Some are relative to the repo, others are absolute paths. Check the settings JSON to find them.
- **Build and test:** Run `swift build` and `swift test` from `PRRadarLibrary/` to verify changes.
- **Daily review script:** `scripts/daily-review.sh` is a scheduling wrapper that runs the `run-all` pipeline on a daily basis (via cron or launchd). Supports `--mode` and `--lookback-hours` flags.
