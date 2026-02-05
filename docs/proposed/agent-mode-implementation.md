# Agent Mode Implementation Plan

## Background

This plan introduces a new "agent mode" paradigm to PRRadar that bypasses the SKILL.md-based approach in favor of direct Claude Agent SDK integration. The current SKILL.md approach relies on Claude Code's skill system, which produces variable outputs because you cannot control structured responses. The new agent mode will use the Python Agent SDK with structured outputs (JSON Schema validation) to create a deterministic, pipeline-based code review system.

**Key motivations:**
- **Structured outputs**: The Agent SDK supports `output_format` with JSON Schema validation, ensuring consistent, parseable responses
- **Pipeline architecture**: Each phase (diff acquisition, rule filtering, rule application, reporting) becomes a distinct CLI operation with file-based artifacts
- **Debuggability**: Intermediate artifacts stored in a dedicated directory (e.g., `tmp/<pr-number>/` or `~/Desktop/code-reviews/<pr-number>/`) allow inspection and debugging at each phase
- **Incremental execution**: Users can run phases independently to verify correctness before proceeding

**Agent SDK key features we'll use:**
- `query()` function for one-off agent calls with structured outputs
- `ClaudeAgentOptions.output_format` with JSON Schema for typed responses
- Built-in tools: `Read`, `Glob`, `Grep`, `Bash` for file operations
- `AgentDefinition` for subagents (one per rule evaluation)

**Code style note:** Phase numbers are for planning purposes only. Do not reference phase numbers in code comments, docstrings, or user-facing messages. Use descriptive names instead (e.g., "rules command" not "Phase 4").

## [x] Phase 1: CLI Infrastructure for Agent Mode

Add the `agent` subcommand group to the existing CLI dispatcher and a convenience shell script.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `cli-architecture` - Command dispatcher pattern, entry points, argument parsing
- `python-code-style` - Method ordering, type annotations

**Technical approach:**
- Extend `__main__.py` to add `agent` subcommand with nested commands
- Add `--output-dir` flag (defaults to `tmp/`) for artifact storage
- Create output directory structure: `<output-dir>/<pr-number>/`
- Add shared utilities for reading/writing JSON artifacts
- Create `agent.sh` convenience script at repo root (overrides output dir to `~/Desktop/code-reviews/`)

**Files to modify:**
- `plugin/skills/pr-review/scripts/__main__.py` - Add agent subcommand group
- Create `plugin/skills/pr-review/scripts/commands/agent/` directory structure

**Files to create:**
- `agent.sh` - Convenience script at repo root

**agent.sh script:**
```bash
#!/bin/bash
# Convenience script for running PRRadar agent mode
# Usage: ./agent.sh diff 123
#        ./agent.sh analyze 456 --rules-dir ./my-rules

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$HOME/Desktop/code-reviews"

# Source .env if it exists (for ANTHROPIC_API_KEY)
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Check for API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Error: ANTHROPIC_API_KEY environment variable is not set"
    echo "Set it in your shell profile or create a .env file in the repo root"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Run the agent command with output dir and pass all arguments
python3 -m scripts agent --output-dir "$OUTPUT_DIR" "$@"
```

**CLI interface:**
```bash
# Via convenience script (recommended) - outputs to ~/Desktop/code-reviews/
./agent.sh diff 123
./agent.sh analyze 456 --rules-dir ./my-rules
./agent.sh comment 123 --dry-run

# Direct Python invocation - outputs to tmp/ by default
python3 -m scripts agent --help
python3 -m scripts agent diff <pr-number> [--output-dir ./tmp]
python3 -m scripts agent analyze <pr-number> [--rules-dir code-review-rules/]
python3 -m scripts agent comment <pr-number> [--dry-run]
```

**Expected outcomes:**
- `agent` subcommand group is functional
- `agent.sh` script provides easy invocation from repo root
- Python CLI defaults to `tmp/<pr-number>/` for artifacts
- `agent.sh` overrides to `~/Desktop/code-reviews/<pr-number>/`
- Help text documents all agent commands
- Output directory structure is created automatically

## [x] Phase 2: Domain Models for Structured Outputs

Define domain models that generate JSON schemas for Claude Agent SDK structured outputs.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `domain-modeling` - Parse-once principle, factory methods, type-safe APIs
- `python-code-style` - Type annotations, method ordering

**Technical approach:**
- Add `claude-agent-sdk` as a dependency
- Define dataclass-based domain models with JSON Schema generation
- Use the Claude Agent SDK directly (no wrapper abstraction)
- Models provide `to_json_schema()` class methods for structured output configuration

**Files to create:**
- `plugin/skills/pr-review/scripts/domain/agent_outputs.py` - Response models (dataclasses with JSON Schema generation)

**Key patterns:**
```python
from dataclasses import dataclass
from typing import ClassVar

@dataclass
class RuleApplicability:
    """Structured output for rule applicability determination."""
    applicable: bool
    reason: str
    confidence: float

    @classmethod
    def json_schema(cls) -> dict:
        return {
            "type": "object",
            "properties": {
                "applicable": {"type": "boolean"},
                "reason": {"type": "string"},
                "confidence": {"type": "number", "minimum": 0, "maximum": 1}
            },
            "required": ["applicable", "reason", "confidence"]
        }

    @classmethod
    def from_dict(cls, data: dict) -> "RuleApplicability":
        return cls(
            applicable=data["applicable"],
            reason=data["reason"],
            confidence=data["confidence"]
        )
```

**Expected outcomes:**
- Domain models define structured output schemas
- Models can parse SDK responses into typed objects
- Direct SDK usage without abstraction layer

## [x] Phase 3: PR Data Acquisition Command (`agent diff`)

Implement the `agent diff` command that fetches and stores PR diff, summary, and comments.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `domain-modeling` - Parse-once principle for GitDiff and PR models
- `identifying-layer-placement` - Command in entry point layer, domain models separate
- `python-code-style` - Type annotations, datetime handling

**Technical approach:**
- Fetch diff using `gh pr diff <pr-number>` (existing infrastructure)
- Fetch PR summary using `gh pr view <pr-number> --json title,body,author,baseRefName,headRefName`
- Fetch PR comments using `gh pr view <pr-number> --json comments,reviews`
- Parse diff into structured `GitDiff` domain model (existing code in `domain/diff.py`)
- **Raw GitHub JSON** for PR metadata, comments, and repo (no wrapper models needed)
- Store artifacts:
  - `<output-dir>/<pr-number>/diff/raw.diff` - Original diff text
  - `<output-dir>/<pr-number>/diff/parsed.json` - Structured diff with hunks (line-annotated)
  - `<output-dir>/<pr-number>/pr.json` - Raw GitHub PR JSON
  - `<output-dir>/<pr-number>/comments.json` - Raw GitHub comments JSON
  - `<output-dir>/<pr-number>/repo.json` - Raw GitHub repo JSON

**Files created:**
- `plugin/skills/pr-review/scripts/commands/agent/diff.py` - Diff command implementation

**Reused existing code:**
- `domain/diff.py` - `GitDiff` and `Hunk` models for parsing

**Expected outcomes:**
- ✅ `python3 -m scripts agent diff 123` fetches and stores PR diff
- ✅ Artifacts are human-readable and inspectable (raw GitHub JSON)
- ✅ Command is idempotent (re-running overwrites cleanly)

## [x] Phase 4: Rule Collection and Filtering Command (`agent rules`)

Implement rule collection and deterministic filtering based on file extensions and regex patterns. No AI is involved in this phase—filtering is purely based on rule metadata.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `domain-modeling` - Rule domain model with factory methods
- `creating-services` - RuleLoaderService with constructor-based DI
- `identifying-layer-placement` - Service layer for business logic
- `python-code-style` - Type annotations, method ordering

**Technical approach:**
1. **Load rules**: Recursively collect all `.md` files from rules directory
2. **Parse metadata**: Extract YAML frontmatter (`description`, `category`, `model`, `applies_to`, `grep`)
3. **Filter by file extension** (first pass): For each file in the diff, filter rules by `applies_to.file_extensions`
4. **Filter by grep patterns** (second pass): For each diff hunk, filter rules by `grep.all` and `grep.any` regex patterns
5. **Output**: Create mapping of which rules apply to which diff segments

**Rule YAML frontmatter fields:**
```yaml
---
description: Handle errors explicitly
category: safety
model: claude-sonnet-4-20250514        # optional - Claude model for evaluation
documentation_link: https://example.com/rules/error-handling  # optional - link to rule docs
applies_to:
  file_extensions: [".py", ".js"]     # file extension filter
grep:
  all: ["async\\s+def"]               # regex patterns - ALL must match
  any: ["try", "except", "\\.catch\\("]  # regex patterns - ANY must match
---
```

**Rule markdown body sections:**
- Main content: Instructions for evaluation (what to check, examples)
- `## GitHub Comment`: Template text for PR comments (Claude adapts this to specific violations)

**Filtering logic:**
- A rule applies to a diff segment if:
  1. File extension matches `applies_to.file_extensions` (or no filter specified)
  2. AND diff text matches `grep.all` patterns (all must match, or no filter specified)
  3. AND diff text matches `grep.any` patterns (at least one must match, or no filter specified)

**Store artifacts:**
- `<output-dir>/<pr-number>/rules/all-rules.json` - All collected rules with metadata
- `<output-dir>/<pr-number>/tasks/` - Directory of evaluation task JSON files

**Evaluation task JSON format** (one file per rule+segment combination):
```json
{
  "task_id": "error-handling-a1b2c3",
  "rule": {
    "name": "error-handling",
    "description": "Handle errors explicitly",
    "category": "safety",
    "model": "claude-sonnet-4-20250514",
    "content": "# Error Handling\n\nErrors should be handled explicitly..."
  },
  "segment": {
    "file_path": "src/api/handler.py",
    "hunk_index": 0,
    "start_line": 42,
    "end_line": 58,
    "content": "@@ -42,10 +42,15 @@\n def fetch_data():\n+    try:\n+        result = api.call()\n+    except:\n+        pass"
  }
}
```

Each task file contains everything needed to evaluate—no additional file reads required.

**Files to create:**
- `plugin/skills/pr-review/scripts/commands/agent/rules.py` - Rules command
- `plugin/skills/pr-review/scripts/domain/rule.py` - Rule domain model ✅ (already created)
- `plugin/skills/pr-review/scripts/domain/evaluation_task.py` - EvaluationTask domain model
- `plugin/skills/pr-review/scripts/services/rule_loader.py` - Rule loading service

**Expected outcomes:**
- `python3 -m scripts agent rules 123 --rules-dir ./rules` collects and filters rules
- Filtering is fast and deterministic (no API calls)
- Each task JSON file is self-contained for evaluation
- The evaluate command reads task files and sends directly to Claude

## [x] Phase 5: Rule Evaluation Command (`agent evaluate`)

Implement the core review logic using dedicated subagents per rule.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `domain-modeling` - Evaluation result models with type-safe APIs
- `creating-services` - EvaluationService for orchestration
- `python-code-style` - Type annotations, method ordering

**Technical approach:**
- Read `applicable.json` from previous phase
- For each rule + code segment combination:
  - Call Claude Agent SDK directly with `query()`
  - Agent prompt includes: rule content, code segment, evaluation criteria
  - Structured output captures violation assessment
- Store artifacts:
  - `<output-dir>/<pr-number>/evaluations/<rule-name>-<file-hash>.json` - Per-evaluation results
  - `<output-dir>/<pr-number>/evaluations/summary.json` - Aggregated results

**Files to create:**
- `plugin/skills/pr-review/scripts/commands/agent/evaluate.py` - Evaluate command
- `plugin/skills/pr-review/scripts/domain/evaluation.py` - Evaluation result models

**Structured output schema for evaluation:**
```json
{
  "type": "object",
  "properties": {
    "violates_rule": {"type": "boolean"},
    "score": {"type": "integer", "minimum": 1, "maximum": 10},
    "explanation": {"type": "string"},
    "suggestion": {"type": "string"},
    "github_comment": {"type": "string"},
    "file_path": {"type": "string"},
    "line_number": {"type": "integer"}
  },
  "required": ["violates_rule", "score", "explanation", "github_comment"]
}
```

**Field semantics:**
- `explanation`: Internal reasoning about why code violates or complies with the rule
- `suggestion`: Specific code fix recommendation
- `github_comment`: The actual comment text to post on GitHub (Claude adapts from rule's `## GitHub Comment` template)

Rule files include a `## GitHub Comment` section with a template that Claude adapts to the specific violation context. The rule's `documentation_link` frontmatter field (if present) is appended programmatically by the comment command—not included in the structured output—to ensure consistent formatting.

**Expected outcomes:**
- `python3 -m scripts agent evaluate 123` runs all rule evaluations
- Each evaluation uses a fresh agent context for focus
- Progress is displayed during evaluation
- Individual evaluation results can be inspected

## [x] Phase 6: GitHub Commenting Command (`agent comment`)

Post review comments to GitHub from evaluation results.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `creating-services` - Reuse existing GitHubCommentService
- `dependency-injection` - Inject service dependencies
- `python-code-style` - Type annotations, method ordering

**Technical approach:**
- Read evaluation results from `evaluations/` directory
- Read rule metadata from `tasks/` directory (for `documentation_link`)
- Filter violations by score threshold (default: score >= 5)
- **Compose final comment**: Combine `github_comment` from evaluation with `documentation_link` from rule
  ```
  {github_comment}

  📖 [Learn more]({documentation_link})
  ```
- Use existing `GitHubCommentService` infrastructure
- Support modes:
  - Interactive mode (default): approve each comment before posting
  - Non-interactive mode: post all comments automatically
  - Dry-run mode: preview without posting (non-interactive only)
- Handle rate limiting and error recovery

**Comment composition logic:**
1. Get `github_comment` from evaluation result (Claude-generated, adapted from rule template)
2. Get `documentation_link` from rule metadata (if present)
3. Programmatically append documentation link to ensure consistent formatting
4. Post composed comment to GitHub at the specified file/line

**Files to create:**
- `plugin/skills/pr-review/scripts/commands/agent/comment.py` - Comment command

**Reuse existing code:**
- `services/github_comment.py` - `GitHubCommentService` for posting
- `infrastructure/gh_runner.py` - GitHub API interactions

**Expected outcomes:**
- `python3 -m scripts agent comment 123` runs in interactive mode (default)
- Interactive mode prompts for each comment (y/n/q)
- `--no-interactive` / `-n` posts all comments without prompting
- `--dry-run` previews comments (requires `--no-interactive`)
- `--min-score` filters which violations to post
- Documentation links are consistently appended (not reliant on model output)
- Rate limiting is handled gracefully

## [ ] Phase 7: Report Generation Command (`agent report`)

Generate a summary report from evaluation results for human review.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `domain-modeling` - Report domain model with factory methods
- `creating-services` - ReportGeneratorService in service layer
- `identifying-layer-placement` - Keep domain models pure, services orchestrate
- `python-code-style` - Type annotations, datetime handling

**Technical approach:**
- Read all evaluation results from `evaluations/` directory
- Filter violations by score threshold (default: score >= 5)
- Group violations by severity, file, or rule (configurable)
- Generate multiple output formats:
  - `<output-dir>/<pr-number>/report/summary.json` - Structured JSON report
  - `<output-dir>/<pr-number>/report/summary.md` - Human-readable markdown

**Files to create:**
- `plugin/skills/pr-review/scripts/commands/agent/report.py` - Report command
- `plugin/skills/pr-review/scripts/domain/report.py` - Report domain models
- `plugin/skills/pr-review/scripts/services/report_generator.py` - Report generation service

**Report structure (JSON):**
```json
{
  "pr_number": 123,
  "generated_at": "2025-02-05T10:30:00Z",
  "summary": {
    "total_rules_checked": 15,
    "violations_found": 3,
    "highest_severity": 8
  },
  "violations": [
    {
      "rule_name": "error-handling",
      "score": 8,
      "file": "src/api/handler.py",
      "line": 42,
      "explanation": "...",
      "suggestion": "..."
    }
  ]
}
```

**Expected outcomes:**
- `python3 -m scripts agent report 123 --min-score 5` generates filtered report
- Reports are ready for human review
- Markdown format is suitable for sharing or archiving

## [ ] Phase 8: Full Pipeline Command (`agent analyze`)

Create a convenience command that runs the full pipeline.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `cli-architecture` - Command dispatcher, explicit parameter flow
- `creating-services` - Composite service orchestrating pipeline
- `python-code-style` - Type annotations, method ordering

**Technical approach:**
- Chain: diff → rules → evaluate → report
- Support `--stop-after <phase>` for partial execution
- Support `--skip-to <phase>` to resume from artifacts
- Display progress summary after each phase

**Files to create:**
- `plugin/skills/pr-review/scripts/commands/agent/analyze.py` - Full pipeline command

**CLI interface:**
```bash
# Full pipeline
python3 -m scripts agent analyze 123 --rules-dir ./rules

# Stop after rules phase
python3 -m scripts agent analyze 123 --stop-after rules

# Resume from existing artifacts
python3 -m scripts agent analyze 123 --skip-to evaluate
```

**Expected outcomes:**
- Single command runs entire review pipeline
- Pipeline can be stopped and resumed
- Progress is clearly displayed

## [ ] Phase 9: Validation and Testing

Comprehensive testing of the agent mode implementation.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `testing-services` - Arrange-Act-Assert pattern, mock at boundaries
- `dependency-injection` - Inject mocks via constructor for testability

**Unit tests:**
- Domain model JSON schema generation
- Structured output parsing and validation
- Rule loading and filtering
- Report generation

**Integration tests:**
- End-to-end pipeline on sample PR diffs
- Artifact file structure verification
- JSON Schema validation of all outputs

**Manual validation:**
- Run against real PRs in test repositories
- Verify structured outputs are consistent
- Compare results to SKILL.md-based approach
- Measure cost per review

**Files to create:**
- `plugin/skills/pr-review/scripts/tests/test_agent_outputs.py`
- `plugin/skills/pr-review/scripts/tests/test_agent_commands.py`
- `plugin/skills/pr-review/scripts/tests/fixtures/sample-diff.diff`
- `plugin/skills/pr-review/scripts/tests/fixtures/sample-rules/`

**Success criteria:**
- All unit tests pass
- Pipeline produces valid artifacts for test cases
- Structured outputs match schemas 100% of the time
- Cost per review is within $1-5 range

## Directory Structure After Implementation

```
repo-root/
├── agent.sh                           # Convenience script for agent mode
└── plugin/skills/pr-review/scripts/
    ├── __main__.py                    # Updated with agent subcommand
    ├── commands/
    │   ├── agent/
    │   │   ├── __init__.py
    │   │   ├── diff.py               # agent diff command
    │   │   ├── rules.py              # agent rules command
    │   │   ├── evaluate.py           # agent evaluate command
    │   │   ├── report.py             # agent report command
    │   │   ├── comment.py            # agent comment command
    │   │   └── analyze.py            # agent analyze (full pipeline)
    │   └── ... (existing commands)
    ├── domain/
    │   ├── agent_outputs.py          # Structured output models
    │   ├── rule.py                   # Rule domain model ✅
    │   ├── evaluation_task.py        # Evaluation task (rule + segment)
    │   ├── evaluation.py             # Evaluation result model
    │   ├── report.py                 # Report domain model
    │   └── ... (existing models)
    ├── services/
    │   ├── rule_loader.py            # Rule loading service
    │   ├── report_generator.py       # Report generation service
    │   └── ... (existing services)
    ├── infrastructure/
    │   └── ... (existing infrastructure)
    └── tests/
        ├── test_agent_outputs.py
        ├── test_agent_commands.py
        └── fixtures/
```

## Artifact Directory Structure

```
~/Desktop/code-reviews/           # Output directory when using agent.sh
tmp/                              # Default output directory for direct Python invocation
└── 123/                          # PR number
    ├── metadata.json             # PR metadata, timestamps
    ├── diff/
    │   ├── raw.diff              # Original diff
    │   └── parsed.json           # Structured diff with hunks
    ├── rules/
    │   └── all-rules.json        # All collected rules with metadata
    ├── tasks/                    # Evaluation tasks (rules command output)
    │   ├── error-handling-a1b2c3.json  # Task: rule + code segment
    │   ├── thread-safety-d4e5f6.json
    │   └── ...
    ├── evaluations/              # Evaluation results (evaluate command output)
    │   ├── error-handling-a1b2c3.json  # Result: violation assessment
    │   ├── thread-safety-d4e5f6.json
    │   └── summary.json          # Aggregated results
    └── report/
        ├── summary.json          # Final JSON report
        └── summary.md            # Human-readable markdown
```

## Dependencies

**New Python dependency:**
```
claude-agent-sdk
```

**System requirements (unchanged):**
- Python 3.11+
- `git` CLI
- `gh` (GitHub CLI)

## API Key Configuration

The Claude Agent SDK requires an `ANTHROPIC_API_KEY` environment variable. Options for configuration:

**Option 1: Export in shell profile (recommended for personal use)**
```bash
# Add to ~/.zshrc or ~/.bashrc
export ANTHROPIC_API_KEY="sk-ant-..."
```

**Option 2: Create a `.env` file (gitignored)**
```bash
# .env file in repo root
ANTHROPIC_API_KEY=sk-ant-...
```

The `agent.sh` script will check for the API key and source `.env` if present:
```bash
#!/bin/bash
# ... existing script content ...

# Source .env if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Check for API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Error: ANTHROPIC_API_KEY environment variable is not set"
    echo "Set it in your shell profile or create a .env file in the repo root"
    exit 1
fi

# ... rest of script ...
```

**Files to update:**
- `.gitignore` - Add `.env` to prevent accidental commits
- `agent.sh` - Add API key check and `.env` sourcing
