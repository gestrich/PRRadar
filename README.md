# PRRadar

PRRadar is a **Python application** for AI-powered pull request reviews. It fetches PR diffs, applies rule-based filtering, evaluates code with the Claude Agent SDK, and generates structured reports.

## Architecture: Python-First

The **Python CLI** (`prradar/`) is the core of the project. It contains all business logic, pipeline orchestration, rule evaluation, and Claude Agent SDK integration. All new features and foundational work should be implemented here first.

The **Swift Mac app** (`pr-radar-mac/`) is a **thin native client** that wraps the Python CLI. It invokes `prradar` commands, parses their JSON output, and presents results in a macOS-native UI. The Mac app contains minimal business logic — it passes data to and makes requests of the Python app rather than implementing review logic itself. The Mac app has two targets:

- **GUI** — A SwiftUI application for browsing diffs, reports, and evaluation outputs
- **CLI** — A command-line target mirroring the Python CLI, useful for running and debugging the Mac app without needing a GUI

## Architecture

Both apps follow structured architecture patterns defined as Claude Code plugins:

- **Python app**: [python-architecture](https://github.com/gestrich/python-architecture) — Service Layer pattern, domain models, dependency injection
- **Mac app**: [swift-app-architecture](https://github.com/gestrich/swift-app-architecture) — 4-layer architecture (SDKs → Services → Features → Apps)

## Overview

The Python app provides thorough, focused code reviews by:

1. **Breaking PRs into segments** — Parses diffs into reviewable code chunks
2. **Rule-based filtering** — Determines which rules apply based on file extensions and regex patterns
3. **Focused AI evaluation** — Each rule gets dedicated Claude evaluation for accurate analysis
4. **Structured outputs** — JSON Schema validation ensures consistent, parseable results
5. **Scored reporting** — Violations are prioritized by severity

## Quick Start

```bash
# Set your API key
export ANTHROPIC_API_KEY="sk-ant-..."

# Run a full review pipeline
./agent.sh analyze 123 --rules-dir ./my-rules

# Or run phases individually
./agent.sh diff 123              # Fetch PR diff
./agent.sh rules 123             # Filter applicable rules
./agent.sh evaluate 123          # Run Claude evaluations
./agent.sh report 123            # Generate report
./agent.sh comment 123 --dry-run # Preview GitHub comments
```

## Installation

### Requirements

- **Python 3.11+**
- **git** CLI
- **gh** (GitHub CLI) — `brew install gh` or https://cli.github.com/
- **Anthropic API key**

### Setup

```bash
git clone https://github.com/gestrich/PRRadar.git
cd PRRadar

# Install dependencies
pip install -r requirements.txt

# Configure API key (choose one)
export ANTHROPIC_API_KEY="sk-ant-..."  # Shell profile
# Or create .env file in repo root:
# ANTHROPIC_API_KEY=sk-ant-...
```

## Usage

### Convenience Script (Recommended)

The `agent.sh` script outputs artifacts to `~/Desktop/code-reviews/`:

```bash
./agent.sh diff 123                    # Fetch PR data
./agent.sh rules 123 --rules-dir ./rules  # Filter rules
./agent.sh evaluate 123                # Run evaluations
./agent.sh report 123                  # Generate report
./agent.sh analyze 123                 # Full pipeline
```

### Direct Python Invocation

Outputs to `tmp/` by default:

```bash
python -m prradar agent diff 123
python -m prradar agent rules 123 --rules-dir ./rules
python -m prradar agent evaluate 123
python -m prradar agent report 123 --min-score 5
python -m prradar agent comment 123 --dry-run
```

## Rules

Rules define what PRRadar checks for during reviews. Each rule is a markdown file with YAML frontmatter.

### Rule Format

````yaml
---
description: Brief description of what the rule checks
category: safety
model: claude-sonnet-4-20250514          # Optional: Claude model for this rule
applies_to:
  file_extensions: [".py", ".js", ".ts"]  # File extension filter
grep:
  all: ["async\\s+def"]                   # Regex patterns - ALL must match
  any: ["try", "except", "\\.catch\\("]   # Regex patterns - ANY must match
---

# Rule Title

Detailed explanation with code examples.

## Requirements

Specific patterns to follow.

## What to Check

Guidance for reviewers.

## GitHub Comment

```
Template comment for violations.
```
````

### Frontmatter Fields

| Field | Description |
|-------|-------------|
| `description` | Concise summary of what the rule checks |
| `category` | Groups related rules (e.g., `safety`, `clarity`, `performance`) |
| `model` | Optional Claude model override for this rule |
| `applies_to.file_extensions` | File extensions this rule applies to |
| `grep.all` | Regex patterns that ALL must match in the diff |
| `grep.any` | Regex patterns where at least ONE must match |

### Filtering Logic

A rule is applied to a diff segment when:
1. File extension matches `applies_to.file_extensions` (or no filter specified)
2. AND all `grep.all` patterns match the diff text (or no patterns specified)
3. AND at least one `grep.any` pattern matches (or no patterns specified)

### Example Rule

````yaml
---
description: Handle errors explicitly rather than silently ignoring them
category: safety
model: claude-sonnet-4-20250514
applies_to:
  file_extensions: [".py", ".js", ".ts", ".go", ".swift"]
grep:
  any:
    - "try"
    - "catch"
    - "except"
    - "throw"
    - "raise"
    - "\\.catch\\("
---

# Explicit Error Handling

Errors should be handled explicitly rather than silently ignored.

## Requirements

### Don't Ignore Errors

```python
# Bad: Error silently ignored
try:
    result = risky_operation()
except:
    pass

# Good: Error logged and handled
try:
    result = risky_operation()
except OperationError as e:
    logger.error(f"Operation failed: {e}")
    return default_value
```

## What to Check

1. Bare `except:` or `catch (e) {}` with no handling
2. Silent failures — `pass`, empty catch blocks
3. Overly broad catches — `except Exception`

## GitHub Comment

```
This error is being silently ignored. Consider logging it or handling
it explicitly so failures are visible during debugging and monitoring.
```
````

### Directory Organization

Place your rules in a directory (default: `code-review-rules/` at repo root):

```
my-rules/
├── safety/
│   ├── error-handling.md
│   └── null-checks.md
├── clarity/
│   ├── naming-conventions.md
│   └── comments.md
└── performance/
    └── async-patterns.md
```

See [docs/rule-examples/](docs/rule-examples/) for complete example rules.

## Output Artifacts

Reviews produce artifacts in a structured directory:

```
~/Desktop/code-reviews/123/      # Or tmp/123/ for direct invocation
├── diff/
│   ├── raw.diff                 # Original diff text
│   └── parsed.json              # Structured diff with hunks
├── rules/
│   └── all-rules.json           # All collected rules
├── tasks/                       # Evaluation tasks (rule + segment pairs)
│   ├── error-handling-a1b2c3.json
│   └── ...
├── evaluations/                 # Claude evaluation results
│   ├── error-handling-a1b2c3.json
│   └── summary.json
└── report/
    ├── summary.json             # Final JSON report
    └── summary.md               # Human-readable markdown
```

## Pipeline Phases

PRRadar runs as a sequential pipeline where each phase writes artifacts to disk and the next phase reads them. This makes the pipeline debuggable, resumable, and individually runnable.

```
  1. DIFF
     │  raw.diff, parsed.json
     ▼
  2. FOCUS AREAS
     │  all.json
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
| **Diff** | Fetches the PR diff from GitHub or a local git repo and parses it into structured file changes |
| **Focus Areas** | Breaks the diff into reviewable code units (methods, functions, blocks) |
| **Rules** | Loads rule definitions and filters them by file extension and grep patterns |
| **Tasks** | Creates rule + focus area pairs — one evaluation task per combination |
| **Evaluations** | Sends each task to Claude for analysis, producing scored results |
| **Report** | Aggregates evaluations into a final JSON and markdown summary |

**Resume:** If a run is interrupted, re-running the same command skips already-completed work. The `status` command shows progress across all phases.

```bash
./agent.sh status 123    # Show pipeline progress for PR #123
```

## Mac App

The Mac app is a thin native client that wraps the Python CLI. It should contain no review logic, rule evaluation, or pipeline orchestration — all of that lives in the Python app. When adding new capabilities, implement them in the Python CLI first, then add the corresponding Swift UI/CLI surface.

### Requirements

- macOS 15+, Swift 6.2+
- Python app installed (`pip install -e .`)

### Build & Run

```bash
cd pr-radar-mac
swift build
swift run MacApp
```

### Architecture

The Mac app follows a 4-layer architecture (see [swift-app-architecture](https://github.com/gestrich/swift-app-architecture)):

| Layer | Target | Role |
|-------|--------|------|
| **SDKs** | `PRRadarMacSDK` | CLI command definitions mirroring the Python CLI |
| **Services** | `PRRadarConfigService`, `PRRadarCLIService` | Config management and Python CLI execution |
| **Features** | `PRReviewFeature` | Use cases (e.g., `FetchDiffUseCase`) |
| **Apps** | `MacApp` | SwiftUI views and `@Observable` models |

## Plugin Mode

PRRadar also works as a Claude Code plugin. See [README-Plugin.md](README-Plugin.md) for plugin documentation.

## License

MIT
