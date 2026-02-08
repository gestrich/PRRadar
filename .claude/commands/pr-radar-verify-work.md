# Verify PRRadar Changes Against Test Repo

We have a dedicated test repository at `/Users/bill/Developer/personal/PRRadar-TestRepo` that exists solely for validating real changes against actual PRs. You have full access to this repo and the GitHub account associated with it.

When this command is invoked, verify your recent changes by running the PRRadar tools against that test repo. What exactly you run depends on what we're working on or what the user asks for — often this means running the Python tool to analyze a PR, but it could be any pipeline phase.

## Before Running

1. **Clean the test repo** before running. Previous runs may leave `code-reviews/` directories or detached HEAD state that cause "uncommitted changes" errors:
   ```bash
   cd /Users/bill/Developer/personal/PRRadar-TestRepo
   rm -rf code-reviews
   git checkout main
   ```

2. **Clean old output data** if needed:
   ```bash
   rm -rf ~/Desktop/code-reviews
   ```

## Running the Python CLI

The Python CLI must be run with a proper output directory. Use `agent.sh` (which handles output directory creation) rather than `python -m prradar` directly:

```bash
# Preferred: use agent.sh from the PRRadar project root
cd /Users/bill/Developer/personal/PRRadar
./agent.sh diff 1 --repo-path /Users/bill/Developer/personal/PRRadar-TestRepo

# Or any other command:
./agent.sh analyze 1 --repo-path /Users/bill/Developer/personal/PRRadar-TestRepo --rules-dir /Users/bill/Developer/personal/PRRadar-TestRepo/rules
```

Running `python -m prradar agent diff 1` directly from the test repo will fail because it tries to write to a relative `code-reviews/` path that doesn't exist yet — `agent.sh` creates the output directory under `~/Desktop/code-reviews/`.

## Running the Swift CLI

The Swift CLI must be run from the `pr-radar-mac/` directory and should use the saved `test-repo` configuration:

```bash
cd /Users/bill/Developer/personal/PRRadar/pr-radar-mac
swift run PRRadarMacCLI diff 1 --config test-repo
swift run PRRadarMacCLI status 1 --config test-repo
swift run PRRadarMacCLI analyze 1 --config test-repo
```

The `--config test-repo` flag uses the saved configuration which points to the test repo path and `~/Desktop/code-reviews/` output directory. Without it, the CLI defaults to the `ios` config which points to the work repo.

To see all saved configurations: `swift run PRRadarMacCLI config list`

## Discovering Available Commands

Both CLIs have built-in help. Use these to explore available commands rather than guessing:

```bash
# Python CLI
python -m prradar --help
python -m prradar agent --help
python -m prradar agent diff --help

# Swift CLI (from pr-radar-mac/)
swift run PRRadarMacCLI --help
swift run PRRadarMacCLI diff --help
swift run PRRadarMacCLI config --help
```

There are other commands beyond these examples — explore with `--help` as needed.
