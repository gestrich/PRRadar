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

Rules define what PRRadar checks for during reviews. Each rule is a markdown file with YAML frontmatter.

### Rule Format

````yaml
---
description: Brief description of what the rule checks
category: safety
applies_to:
  file_extensions: [".swift", ".m", ".h"]
grep:
  all: ["async\\s+def"]
  any: ["try", "except"]
---

# Rule Title

Detailed explanation with code examples.
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
