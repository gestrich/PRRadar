---
name: pr-review
description: AI-powered pull request review tool that analyzes code changes using customizable rules. Breaks down PRs into chunks, applies focused review rules, and generates prioritized feedback.
user-invocable: true
argument-hint: "[pr-number-or-commit] [rules-directory]"
---

# PRRadar: PR Review Tool

An AI-powered pull request review tool that provides thorough, focused code reviews by breaking down changes and applying specialized review rules.

## When to Use This Skill

Use this skill when you need to:
- Review a pull request with custom code review rules
- Analyze commits against repository-specific standards
- Get detailed, rule-based feedback on code changes
- Apply organizational coding standards systematically

## Overview

PRRadar addresses a fundamental limitation of existing AI code review tools: they miss issues because they lack focus and specificity. This tool solves that by:

1. **Chunking PRs into smaller pieces** - Breaking down changes into focused, reviewable segments
2. **Rule-based reviews** - Each rule checks one specific thing with dedicated focus
3. **Intelligent rule application** - Determines which rules apply to which code changes
4. **Dedicated AI agents** - Each rule gets its own AI context for focused analysis
5. **Scored reporting** - Violations are prioritized by severity

> **⚠️ IMPORTANT: Subagent Requirement**
>
> PRRadar MUST use subagents (Task tool with `model: "sonnet"`) for each rule evaluation. **Do NOT skip subagents** regardless of diff size. Even small diffs require dedicated subagent analysis per rule to catch subtle violations. This is non-negotiable - the quality of review depends on focused, isolated rule evaluation.

## Architecture

```
┌─────────────┐
│ Input       │  (PR number, commit SHA, rules directory)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Get Diff    │  (gh pr diff / git diff)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Segment     │  (parse into logical units)
│ Changes     │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Filter      │  (match segments to applicable rules)
│ Rules       │
└──────┬──────┘
       │
       ▼
┌───────────────────────────┐
│ Execute Reviews           │
│ (dedicated agent per rule)│
└──────┬────────────────────┘
       │
       ▼
┌─────────────┐
│ Generate    │  (prioritized feedback report)
│ Report      │
└─────────────┘
```

## Usage

```
/pr-review [pr-number-or-commit] [rules-directory]
```

### Arguments

1. **pr-number-or-commit** (required): What to review
   - PR number: `123` or `#123`
   - PR URL: `https://github.com/owner/repo/pull/123`
   - Commit SHA: `abc1234` (reviews from commit to HEAD)

2. **rules-directory** (optional): Path to the directory containing review rules
   - **Default**: `code-review-rules` at the repository root
   - Can be absolute or relative path
   - PRRadar recursively traverses all subdirectories to collect every `.md` file as a rule
   - Example: `./rules` or `/path/to/custom/rules`

### Examples

```bash
# Review PR #123 using default rules (code-review-rules/)
/pr-review 123

# Review PR #123 with custom rules directory
/pr-review 123 ./my-rules

# Review PR using full URL (default rules)
/pr-review https://github.com/gestrich/PRRadar/pull/5

# Review commits from abc1234 to HEAD
/pr-review abc1234

# Review using absolute path to rules
/pr-review #456 /Users/bill/my-project/review-rules
```

## Rules Directory Structure

Rules are markdown files (`.md`) that define what to check for. PRRadar **recursively traverses all subdirectories** within the rules directory to collect every rule file, regardless of subdirectory names. After collecting all rules, it determines which apply to the current diff based on frontmatter filters.

**Important**: Do not skip directories based on their names. Traverse the entire directory tree and collect all `.md` files as potential rules.

Each rule:
- Has a single responsibility (checks one specific thing)
- Includes YAML frontmatter with metadata
- Contains the review criteria in markdown

### Rule File Format

```markdown
---
description: Brief description of what this rule checks for
documentation: https://github.com/org/repo/docs/RuleName.md
applies_to:
  file_extensions: [".swift", ".m", ".h"]
---

# Rule Content

Detailed explanation of the rule, what to check for,
examples of violations, and how to fix them.
```

### Rule Frontmatter Fields

- **description**: Brief summary of the rule's purpose
- **documentation** (optional): Link to detailed documentation
- **applies_to.file_extensions** (optional): Only apply to files with these extensions

### Example Rules Directory

Rules can be organized in any directory structure. All `.md` files are collected recursively:

```
rules/
├── error-handling.md          # collected as "error-handling"
├── thread-safety.md           # collected as "thread-safety"
├── nullability/               # subdirectory - traversed regardless of name
│   ├── nullability_h_files.md # collected as "nullability/nullability_h_files"
│   └── nullability_m_files.md # collected as "nullability/nullability_m_files"
└── architecture/              # another subdirectory
    ├── layer-violations.md    # collected as "architecture/layer-violations"
    └── dependency-injection.md
```

The rule name is the relative path from the rules directory without the `.md` extension.

## How PRRadar Works

### Phase 1: Diff Acquisition

PRRadar fetches the diff from either:
- **Local repository**: Uses `git diff` for commits
- **GitHub API**: Uses `gh pr diff` for pull requests

### Phase 2: Code Segmentation

The diff is broken into logical segments:
- Methods and functions
- Class/interface declarations
- Property definitions
- Configuration changes

Each segment is analyzed independently for focused review.

### Phase 3: Rule Filtering

First, PRRadar **collects all rules** by recursively traversing the rules directory and gathering every `.md` file. Then, for each segment, it determines which rules apply based on:
- File extension matching (from `applies_to.file_extensions` frontmatter)
- Code pattern detection (grep-based)
- Rule metadata

This pre-filtering keeps review focused and costs manageable.

### Phase 4: Dedicated Review Agents

**CRITICAL: You MUST use subagents for rule evaluation.** Even if the diff is small or appears simple, do NOT skip subagents or reason that the diff is "small enough" to review inline. Each rule requires dedicated, focused attention that only a subagent can provide.

For each segment + rule combination:
- **MUST** spawn a dedicated subagent using the Task tool with `model: "sonnet"` (latest sonnet model)
- Subagent reads the rule and segment
- Subagent evaluates: Does this violate the rule?
- Subagent scores the violation (1-10 scale)
- Subagent provides specific feedback

**Why subagents are mandatory:**
- Each rule requires fresh, focused context to catch violations
- Reviewing multiple rules in a single context causes attention dilution
- Small diffs often have subtle issues that require dedicated analysis
- The cost of subagents is acceptable ($1-5 per thorough review)

### Phase 5: Report Generation

PRRadar generates a comprehensive report:
- Violations grouped by severity
- Each violation includes:
  - Rule that was violated
  - Location in code (file, line number)
  - Explanation of the issue
  - Suggested fix
  - Links to documentation

### Scoring System

Scores measure **how clearly the code violates the rule**:

- **1-2**: No violation - code follows this rule well
- **3-4**: Unlikely violation - minor ambiguity but probably fine
- **5-6**: Unclear - could be a violation depending on context
- **7-8**: Likely violation - code appears to break the rule
- **9-10**: Clear violation - code definitively breaks the rule

Only violations (score ≥ 5) are included in the final report.

## Running PRRadar

### Command-Line Interface

PRRadar is implemented as a Swift package (`pr-radar-mac/`). While the skill provides guidance for Claude to use the tool, you can also run it directly:

```bash
# From pr-radar-mac/ directory
swift run PRRadarMacCLI --help

# Pipeline commands
swift run PRRadarMacCLI analyze 1 --config test-repo
swift run PRRadarMacCLI diff 1 --config test-repo
swift run PRRadarMacCLI status 1 --config test-repo
```

### System Requirements

- macOS 15+, Swift 6.2+
- `git` command-line tool
- `gh` (GitHub CLI) for PR reviews
- Python 3.11+ (only for the Claude Agent SDK bridge)

### Installation

```bash
# Clone the repository
git clone https://github.com/gestrich/PRRadar.git
cd PRRadar/pr-radar-mac

# Build
swift build

# Install bridge dependencies
pip install -r bridge/requirements.txt

# Test the CLI
swift run PRRadarMacCLI --help
```

## Value Proposition

- **Cost model**: Spending $1-5 per thorough PR review is acceptable for high-quality feedback
- **Depth over speed**: More thorough than existing tools, catches issues they miss
- **Customizable rules**: Define exactly what matters for your codebase
- **Transparent and debuggable**: Each phase produces artifacts for inspection
- **Scales expertise**: Codify senior engineer knowledge into reusable rules

## Plugin Installation

Install PRRadar as a Claude Code plugin:

```bash
# Via Claude Code marketplace
/plugin marketplace add gestrich/PRRadar
/plugin install prradar@bill-prradar --scope project

# Local development
claude --plugin-dir ~/path/to/PRRadar/plugin
```

## License

MIT License - See [LICENSE](../../LICENSE) for details.
