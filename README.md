# PRRadar

A Python CLI tool for AI-powered pull request reviews using the Claude Agent SDK.

## Overview

PRRadar provides thorough, focused code reviews by:

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
python3 -m scripts agent diff 123
python3 -m scripts agent rules 123 --rules-dir ./rules
python3 -m scripts agent evaluate 123
python3 -m scripts agent report 123 --min-score 5
python3 -m scripts agent comment 123 --dry-run
```

## Rules

Rules define what PRRadar checks for during reviews. Each rule is a markdown file with YAML frontmatter.

### Rule Format

```yaml
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
```

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

```yaml
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
```

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

## Architecture

PRRadar uses a pipeline architecture with file-based artifacts between phases:

```
diff → rules → tasks → evaluate → report → comment
```

Each phase is independently runnable, making the pipeline debuggable and resumable.

## Plugin Mode

PRRadar also works as a Claude Code plugin. See [README-Plugin.md](README-Plugin.md) for plugin documentation.

## License

MIT
