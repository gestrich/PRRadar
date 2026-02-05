# PRRadar

An AI-powered pull request review tool that provides thorough, focused code reviews by breaking down changes and applying specialized review rules.

## Overview

PRRadar addresses a fundamental limitation of existing AI code review tools: they miss issues because they lack focus and specificity. This tool solves that by:

1. **Chunking PRs into smaller pieces** - Breaking down changes into focused, reviewable segments
2. **Rule-based reviews** - Each rule checks one specific thing with dedicated focus
3. **Intelligent rule application** - Determines which rules apply to which code changes
4. **Dedicated AI subagents** - Each rule gets its own sonnet-model subagent for focused analysis (mandatory, even for small diffs)
5. **Scored reporting** - Violations are prioritized by severity

## Architecture

Built as a **Claude Code plugin** that can be used with any repository by providing rule files in the expected format. This makes it reusable and open-source-friendly.

The tool will operate in a pipeline:
1. Fetch PR changes
2. Break into reviewable chunks
3. Filter applicable rules
4. Execute focused reviews
5. Generate prioritized report
6. Allow manual filtering
7. Post feedback to GitHub

## Value Proposition

- **Cost model**: Spending $1-5 per thorough PR review is acceptable for high-quality feedback
- **Depth over speed**: More thorough than existing tools, catches issues they miss
- **Customizable rules**: Define exactly what matters for your codebase
- **Transparent and debuggable**: Each phase produces artifacts for inspection
- **Scales expertise**: Codify senior engineer knowledge into reusable rules

## Dependencies

### Python Requirements
- **Python 3.11 or higher**
- No external Python packages required - uses only standard library modules

### System Requirements
- **git**: For repository operations
- **gh** (GitHub CLI): For GitHub API interactions
  - Install on macOS: `brew install gh`
  - Other platforms: https://cli.github.com/

### Installation

#### As a Claude Code Plugin (Recommended)

Install PRRadar as a Claude Code plugin for easy access in any project:

```bash
# From Claude Code marketplace (when published)
/plugin marketplace add gestrich/PRRadar
/plugin install prradar@bill-prradar --scope project

# Or for local development
claude --plugin-dir ~/path/to/PRRadar/plugin
```

Once installed, use PRRadar with:

```
/pr-review [pr-number-or-commit] [rules-directory]
```

The rules directory is **optional** - if not specified, PRRadar will look for a `code-review-rules` directory at the repository root.

For example:
```
/pr-review 123                              # Uses default code-review-rules/
/pr-review 123 ./my-rules                   # Uses custom rules directory
/pr-review https://github.com/owner/repo/pull/456
```

#### Direct Installation

For standalone use or development:

```bash
# Clone the repository
git clone https://github.com/gestrich/PRRadar.git
cd PRRadar

# Verify Python version
python3 --version  # Should be 3.11+

# Verify system dependencies
git --version
gh --version

# Test the CLI
python3 -m scripts --help
```

## Rules

Rules are the core product of PRRadar. Each rule checks one specific thing with dedicated focus, making reviews more accurate and actionable.

**How rules work:**
- Each rule has a single responsibility - checking one specific pattern or practice
- Rules include severity levels to prioritize feedback
- Rules can link to documentation explaining the "why"
- Rules are version controlled alongside your team's code standards
- The system filters which rules apply to which code changes
- Each applicable rule gets its own dedicated AI agent for focused review

The rule library becomes a living document of your team's code standards and best practices.
