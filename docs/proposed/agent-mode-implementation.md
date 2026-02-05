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

## [ ] Phase 3: PR Data Acquisition Command (`agent diff`)

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
- Store artifacts:
  - `<output-dir>/<pr-number>/diff/raw.diff` - Original diff text
  - `<output-dir>/<pr-number>/diff/parsed.json` - Structured diff with hunks
  - `<output-dir>/<pr-number>/pr.json` - PR metadata (title, body, author, branches)
  - `<output-dir>/<pr-number>/comments.json` - PR comments and review comments
  - `<output-dir>/<pr-number>/metadata.json` - Fetch metadata (timestamp, repo)

**Files to create:**
- `plugin/skills/pr-review/scripts/commands/agent/diff.py` - Diff command implementation

**Reuse existing code:**
- `infrastructure/gh_runner.py` - For `gh pr diff` execution
- `domain/diff.py` - `GitDiff` and `Hunk` models for parsing

**Expected outcomes:**
- `python3 -m scripts agent diff 123` fetches and stores PR diff
- Artifacts are human-readable and inspectable
- Command is idempotent (re-running overwrites cleanly)

## [ ] Phase 4: Rule Collection and Filtering Command (`agent rules`)

Implement rule collection with AI-assisted applicability determination.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `domain-modeling` - Rule domain model with factory methods
- `creating-services` - RuleLoaderService with constructor-based DI
- `identifying-layer-placement` - Service layer for business logic
- `python-code-style` - Type annotations, method ordering

**Technical approach:**
- Recursively collect all `.md` files from rules directory
- Parse YAML frontmatter for metadata (`applies_to.file_extensions`, `description`)
- For each rule + diff combination, use Agent SDK to determine applicability:
  - Use structured output: `{"applicable": bool, "reason": string, "confidence": float}`
  - Agent has access to `Read` tool to examine rule content and diff
- Store artifacts:
  - `<output-dir>/<pr-number>/rules/all-rules.json` - All collected rules with metadata
  - `<output-dir>/<pr-number>/rules/applicable.json` - Filtered rules per file/hunk

**Files to create:**
- `plugin/skills/pr-review/scripts/commands/agent/rules.py` - Rules command
- `plugin/skills/pr-review/scripts/domain/rule.py` - Rule domain model
- `plugin/skills/pr-review/scripts/services/rule_loader.py` - Rule loading service

**Structured output schema for applicability:**
```json
{
  "type": "object",
  "properties": {
    "applicable": {"type": "boolean"},
    "reason": {"type": "string"},
    "confidence": {"type": "number", "minimum": 0, "maximum": 1}
  },
  "required": ["applicable", "reason", "confidence"]
}
```

**Expected outcomes:**
- `python3 -m scripts agent rules 123 --rules-dir ./rules` determines applicable rules
- Each rule's applicability is logged with reasoning
- Artifacts show which rules will be checked for which code

## [ ] Phase 5: Rule Evaluation Command (`agent evaluate`)

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
    "file_path": {"type": "string"},
    "line_number": {"type": "integer"}
  },
  "required": ["violates_rule", "score", "explanation"]
}
```

**Expected outcomes:**
- `python3 -m scripts agent evaluate 123` runs all rule evaluations
- Each evaluation uses a fresh agent context for focus
- Progress is displayed during evaluation
- Individual evaluation results can be inspected

## [ ] Phase 6: Report Generation Command (`agent report`)

Generate the final review report from evaluation results.

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
- Markdown format is suitable for GitHub PR comments

## [ ] Phase 7: GitHub Commenting Command (`agent comment`)

Post review comments to GitHub from the generated report.

**Best practices:** Apply skills from [gestrich/python-architecture](https://github.com/gestrich/python-architecture):
- `creating-services` - Reuse existing GitHubCommentService
- `dependency-injection` - Inject service dependencies
- `python-code-style` - Type annotations, method ordering

**Technical approach:**
- Read report from previous phase
- Use existing `GitHubCommentService` infrastructure
- Support modes:
  - Individual inline comments per violation
  - Single summary comment with all violations
  - Dry-run mode to preview without posting
- Handle rate limiting and error recovery

**Files to create:**
- `plugin/skills/pr-review/scripts/commands/agent/comment.py` - Comment command

**Reuse existing code:**
- `services/github_comment.py` - `GitHubCommentService` for posting
- `infrastructure/gh_runner.py` - GitHub API interactions

**Expected outcomes:**
- `python3 -m scripts agent comment 123` posts review comments
- `--dry-run` shows what would be posted without posting
- Comments link to documentation when available
- Rate limiting is handled gracefully

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
    │   ├── rule.py                   # Rule domain model
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
    │   ├── all-rules.json        # All collected rules
    │   └── applicable.json       # Filtered rules per file
    ├── evaluations/
    │   ├── error-handling-a1b2c3.json  # Individual evaluations
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
