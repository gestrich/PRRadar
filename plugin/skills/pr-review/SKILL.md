---
name: pr-review
description: AI-powered pull request review tool that analyzes code changes using customizable rules. Breaks down PRs into chunks, applies focused review rules, and generates prioritized feedback.
user-invocable: true
argument-hint: "[rules-directory] [pr-number-or-commit]"
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
/pr-review [rules-directory] [pr-number-or-commit]
```

### Arguments

1. **rules-directory** (required): Path to the directory containing review rules
   - Can be absolute or relative path
   - Directory should contain `.md` files defining review rules
   - Example: `./rules` or `/path/to/custom/rules`

2. **pr-number-or-commit** (required): What to review
   - PR number: `123` or `#123`
   - PR URL: `https://github.com/owner/repo/pull/123`
   - Commit SHA: `abc1234` (reviews from commit to HEAD)

### Examples

```bash
# Review PR #123 using rules in ./rules directory
/pr-review ./rules 123

# Review PR using full URL
/pr-review ./rules https://github.com/gestrich/PRRadar/pull/5

# Review commits from abc1234 to HEAD
/pr-review ./rules abc1234

# Review using absolute path to rules
/pr-review /Users/bill/my-project/review-rules #456
```

## Rules Directory Structure

Rules are markdown files that define what to check for. Each rule:
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

```
rules/
├── error-handling.md
├── thread-safety.md
├── nullability/
│   ├── nullability_h_files.md
│   └── nullability_m_files.md
└── architecture/
    ├── layer-violations.md
    └── dependency-injection.md
```

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

For each segment, PRRadar determines which rules apply based on:
- File extension matching
- Code pattern detection (grep-based)
- Rule metadata

This pre-filtering keeps review focused and costs manageable.

### Phase 4: Dedicated Review Agents

For each segment + rule combination:
- Spawn a dedicated AI agent
- Agent reads the rule and segment
- Agent evaluates: Does this violate the rule?
- Agent scores the violation (1-10 scale)
- Agent provides specific feedback

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

PRRadar is implemented as Python scripts in the `scripts/` directory. While the skill provides guidance for Claude to use the tool, you can also run it directly:

```bash
# From repository root
python3 -m scripts --help

# Review a PR
python3 -m scripts review-pr --rules ./rules --pr 123

# Review local commits
python3 -m scripts review-commit --rules ./rules --commit abc1234
```

### System Requirements

- Python 3.11 or higher (uses standard library only)
- `git` command-line tool
- `gh` (GitHub CLI) for PR reviews

### Installation

```bash
# Clone the repository
git clone https://github.com/gestrich/PRRadar.git
cd PRRadar

# Verify Python version
python3 --version  # Should be 3.11+

# Verify dependencies
git --version
gh --version

# Test the CLI
python3 -m scripts --help
```

## Value Proposition

- **Cost model**: Spending $1-5 per thorough PR review is acceptable for high-quality feedback
- **Depth over speed**: More thorough than existing tools, catches issues they miss
- **Customizable rules**: Define exactly what matters for your codebase
- **Transparent and debuggable**: Each phase produces artifacts for inspection
- **Scales expertise**: Codify senior engineer knowledge into reusable rules

## Current Implementation Status

PRRadar is being built in phases:

- ✅ **Phase 1**: Migrated existing code and GitHub Actions
- 🔄 **Phase 2**: Core plugin structure (current phase)
- ⏳ **Phase 3**: Diff acquisition (local and remote)
- ⏳ **Phase 4**: Diff segmentation and chunking
- ⏳ **Phase 5**: Rule management system
- ⏳ **Phase 6**: AI review execution engine
- ⏳ **Phase 7**: Review report generation
- ⏳ **Phase 8**: GitHub integration
- ⏳ **Phase 9**: Local iteration and rule development
- ⏳ **Phase 10**: Documentation and packaging

See [docs/proposed/pr-review-tool-implementation.md](../../docs/proposed/pr-review-tool-implementation.md) for the complete implementation plan.

## Plugin Installation

Once published, you can install PRRadar as a Claude Code plugin:

```bash
# Via Claude Code marketplace
/plugin marketplace add gestrich/PRRadar
/plugin install prradar@bill-prradar --scope project

# Local development
claude --plugin-dir ~/path/to/PRRadar/plugin
```

## Contributing

PRRadar is designed to be extensible through rules. To contribute:

1. **Add new rules**: Create markdown files in your rules directory
2. **Share rules**: Submit PRs with useful rules for common patterns
3. **Improve segmentation**: Enhance the code chunking logic
4. **Add language support**: Extend to more programming languages

## License

MIT License - See [LICENSE](../../LICENSE) for details.
