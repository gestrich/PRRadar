# PRRadar

PRRadar is a **Swift application** for AI-powered pull request reviews. It fetches PR diffs, applies rule-based filtering, evaluates code with the Claude Agent SDK, and generates structured reports.

## Overview

PRRadar addresses a fundamental limitation of existing AI code review tools: they miss issues because they lack focus and specificity. This tool solves that by:

1. **Breaking PRs into segments** — Parses diffs into reviewable code chunks
2. **Rule-based filtering** — Determines which rules apply based on file extensions and regex patterns
3. **Focused AI evaluation** — Each rule gets dedicated Claude evaluation for accurate analysis
4. **Structured outputs** — JSON Schema validation ensures consistent, parseable results
5. **Scored reporting** — Violations are prioritized by severity

## Quick Start

```bash
cd pr-radar-mac

# Build
swift build

# Install bridge dependencies (Claude Agent SDK)
pip install -r bridge/requirements.txt

# Set your API key
export ANTHROPIC_API_KEY="sk-ant-..."

# Run a full review pipeline
swift run PRRadarMacCLI analyze 1 --config test-repo

# Or run phases individually
swift run PRRadarMacCLI diff 1 --config test-repo
swift run PRRadarMacCLI rules 1 --config test-repo
swift run PRRadarMacCLI evaluate 1 --config test-repo
swift run PRRadarMacCLI report 1 --config test-repo
swift run PRRadarMacCLI comment 1 --config test-repo --dry-run
swift run PRRadarMacCLI status 1 --config test-repo
```

## Requirements

- **macOS 15+**, **Swift 6.2+**
- **git** CLI
- **gh** (GitHub CLI) — `brew install gh` or https://cli.github.com/
- **Python 3.11+** — only for the Claude Agent SDK bridge
- **Anthropic API key**

## Architecture

The app follows a 4-layer architecture (see [swift-app-architecture](https://github.com/gestrich/swift-app-architecture)):

| Layer | Target | Role |
|-------|--------|------|
| **SDKs** | `PRRadarMacSDK` | CLI command definitions (git, gh, claude bridge) |
| **Services** | `PRRadarModels`, `PRRadarConfigService`, `PRRadarCLIService` | Domain models, config, business logic |
| **Features** | `PRReviewFeature` | Use cases (FetchDiffUseCase, EvaluateUseCase, etc.) |
| **Apps** | `MacApp`, `PRRadarMacCLI` | SwiftUI GUI and CLI entry points |

### Python Bridge

The only Python code is a minimal bridge script (`pr-radar-mac/bridge/claude_bridge.py`) that wraps the Claude Agent SDK `query()` call. This is necessary because the Claude Agent SDK is Python-only.

## Rules

Rules define what PRRadar checks for during reviews. Each rule is a markdown file with YAML frontmatter that describes what to look for, which files it applies to, and how violations are detected.

### Rule Directories

Rules are organized into directories. Each repository configuration can have multiple named rule paths:

```
my-rules/
├── safety/
│   ├── sql-injection.md
│   └── xss-prevention.md
├── apis-apple/
│   ├── nullability-objc.md
│   ├── check-generics.sh          # Script referenced by generics rule
│   └── generics-objc.md
└── clarity/
    └── descriptive-names.md
```

Rule paths are configured per repository. Paths can be relative (resolved against the repo root) or absolute:

```json
{
  "name": "my-project",
  "repoPath": "/path/to/repo",
  "rulePaths": [
    { "name": "main", "path": "code-review-rules", "isDefault": true },
    { "name": "experiment", "path": "/Users/me/Desktop/experimental-rules" }
  ]
}
```

PRRadar recursively scans each rule directory for `.md` files. Subdirectory structure is for organization only — it doesn't affect behavior.

### Rule Format

Each rule is a markdown file with YAML frontmatter:

````yaml
---
description: Brief description of what the rule checks
category: safety
applies_to:
  file_patterns: ["*.swift", "*.m", "*.h"]
  exclude_patterns: ["**/Generated/**"]
grep:
  all: ["async\\s+def"]
  any: ["try", "except"]
---

# Rule Title

Detailed explanation of the rule with code examples showing good and
bad patterns. This content is sent to Claude for AI-evaluated rules.
````

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `description` | Yes | Concise summary of what the rule checks |
| `category` | Yes | Groups related rules (e.g., `safety`, `correctness`, `clarity`) |
| `applies_to.file_patterns` | No | Glob patterns for files this rule applies to (e.g., `["*.h", "*.m"]`) |
| `applies_to.exclude_patterns` | No | Glob patterns for files to exclude (e.g., `["**/Tests/**"]`) |
| `grep.all` | No | Regex patterns that ALL must match in the diff |
| `grep.any` | No | Regex patterns where at least ONE must match |
| `model` | No | Claude model override for this rule (AI mode only) |
| `documentation_link` | No | URL to relevant documentation |
| `new_code_lines_only` | No | When `true`, only check added lines (not context/removed lines) |
| `violation_script` | No | Path to a shell script for programmatic violation detection |
| `violation_regex` | No | Regex pattern for simple pattern-based violation detection |
| `violation_message` | No | Default message for regex violations |
| `focus_type` | No | `file` (default) or `method` — controls how the diff is segmented |

### Filtering Logic

A rule is applied to a diff segment when:
1. File path matches `applies_to.file_patterns` (or no patterns specified) AND does not match `exclude_patterns`
2. AND all `grep.all` regex patterns match the diff text (or none specified)
3. AND at least one `grep.any` regex pattern matches (or none specified)

File patterns use glob syntax: `*.swift` matches the filename, `**/*.swift` matches any path depth.

### Evaluation Modes

Each rule uses one of three evaluation modes, determined by which frontmatter fields are set:

#### AI Evaluation (default)

When neither `violation_script` nor `violation_regex` is set, PRRadar sends the rule content and diff to Claude for evaluation. The markdown body of the rule serves as the prompt — include code examples, good/bad patterns, and clear criteria.

```yaml
---
description: Prefer descriptive variable names over abbreviations
category: clarity
applies_to:
  file_patterns: ["*.swift"]
---

# Descriptive Variable Names

Variable names should clearly communicate their purpose...

## What to Check

1. Single-letter names outside loop counters
2. Vowel-removed abbreviations like `usr`, `msg`, `cfg`
```

AI evaluation uses Claude Sonnet by default. Override with the `model` field.

#### Script Evaluation

Set `violation_script` to a path (relative to the rules directory) to run a shell script that detects violations programmatically. This is faster than AI and fully deterministic.

```yaml
---
description: Ensures Objective-C collection types use lightweight generics
category: correctness
violation_script: apis-apple/check-generics-objc.sh
applies_to:
  file_patterns: ["*.h", "*.m"]
grep:
  any: ["NSArray", "NSDictionary", "NSSet"]
---
```

The script receives three arguments:

```
./check-generics-objc.sh FILE START_LINE END_LINE
```

It must output tab-delimited violations to stdout:

```
LINE_NUMBER<TAB>CHARACTER_POSITION<TAB>SCORE[<TAB>COMMENT]
```

| Column | Description |
|--------|-------------|
| `LINE_NUMBER` | Line number in the file (positive integer) |
| `CHARACTER_POSITION` | Column position (0 for line-level) |
| `SCORE` | Severity 1-10 (10 = most severe) |
| `COMMENT` | Optional. Falls back to `violation_message` or `description` |

Exit code 0 = success (violations may or may not be present). Non-zero = error.

Only violations on changed lines in the diff are reported. The script can scan broadly — PRRadar handles the filtering.

#### Regex Evaluation

Set `violation_regex` for simple pattern matching without a script. Each regex match on a changed line becomes a violation.

```yaml
---
description: Do not use NS_ASSUME_NONNULL_BEGIN
category: correctness
violation_regex: "NS_ASSUME_NONNULL_BEGIN"
violation_message: "Do not use `NS_ASSUME_NONNULL_BEGIN`. Add explicit annotations instead."
applies_to:
  file_patterns: ["*.h"]
grep:
  any: ["NS_ASSUME_NONNULL_BEGIN"]
---
```

`violation_script` and `violation_regex` are mutually exclusive — a rule cannot use both.

## Pipeline Phases

PRRadar runs as a sequential pipeline where each phase writes artifacts to disk and the next phase reads them. This makes the pipeline debuggable, resumable, and individually runnable.

```
  1. DIFF
     │  raw.diff, parsed.json
     ▼
  2. FOCUS AREAS
     │  method.json, file.json
     ▼
  3. RULES
     │  all-rules.json
     ▼
  4. TASKS
     │  {id}.json  (one per rule + focus area pair)
     ▼
  5. EVALUATIONS
     │  {id}.json, summary.json
     ▼
  6. REPORT
        summary.json, summary.md
```

| Phase | What it does |
|-------|-------------|
| **Diff** | Fetches the PR diff from GitHub and parses it into structured file changes |
| **Focus Areas** | Breaks the diff into reviewable code units (methods, functions, blocks) |
| **Rules** | Loads rule definitions and filters them by file extension and grep patterns |
| **Tasks** | Creates rule + focus area pairs — one evaluation task per combination |
| **Evaluations** | Sends each task to Claude for analysis, producing scored results |
| **Report** | Aggregates evaluations into a final JSON and markdown summary |

**Resume:** If a run is interrupted, re-running the same command skips already-completed work. The `status` command shows progress across all phases.

## GUI App

```bash
cd pr-radar-mac
swift run MacApp
```

The SwiftUI GUI provides a visual interface for browsing diffs, reports, and evaluation outputs.

## Plugin Mode

PRRadar also works as a Claude Code plugin. The plugin is in `plugin/` and provides the `/pr-review` skill. See the [plugin SKILL.md](plugin/skills/pr-review/SKILL.md) for details.

## License

MIT
