# PR Review Tool Implementation Plan

## Background

This plan details the phased implementation of PRRadar. The tool architecture and vision are documented in the main README.md. This document focuses on the technical implementation approach, breaking the work into phases that build on strong foundations.

## Phases

## - [x] Phase 1: Migrate Existing Code and GitHub Actions

Migrate the existing code review implementation into this repository:

**Technical approach:**
- Copy all code from the source directory **except** the rules
- Rules remain repository-specific and should not be migrated
- Migrate GitHub Actions workflows:
  - Copy `pr-radar.yml` workflow
  - Copy `pr-radar-mention.yml` workflow
  - Adapt workflows to work with this repository's structure
  - Update any hardcoded paths or repository-specific references

**Files to migrate:**
- Python scripts from code-review skill (excluding rules directory)
- GitHub Actions workflows: pr-radar.yml and pr-radar-mention.yml
- Any supporting utilities or helper functions
- Configuration files (adapt as needed)

**Important considerations:**
- Update imports and paths to match new repository structure
- Test that migrated workflows work in this repository context

**Expected outcomes:**
- All existing code review logic is available in this repository
- GitHub Actions workflows are functional
- Foundation is ready for further development
- Existing functionality is preserved and operational

## - [x] Phase 2: Core Plugin Structure

Create the foundational Claude Code plugin structure:

**Technical approach:**
- Create Anthropic plugin that can be invoked as a Claude Code skill
- Accept path to rules directory as input parameter
- Set up plugin manifest and configuration
- Establish command-line argument parser
- Integrate with migrated code from Phase 1

**Files created:**
- `.claude-plugin/marketplace.json` - Marketplace registration
- `plugin/.claude-plugin/plugin.json` - Plugin manifest
- `plugin/skills/pr-review/SKILL.md` - Main pr-review skill
- `plugin/LICENSE` - MIT license for plugin
- Updated README.md with plugin installation instructions

**Expected outcomes:**
- ✅ Plugin can be invoked from Claude Code in any repository
- ✅ Clean interface for passing parameters (`/pr-review [pr-or-commit] [rules-dir]` where rules-dir defaults to `code-review-rules/`)
- ✅ Foundation is in place for pipeline-based processing
- ✅ Plugin follows Claude Code plugin best practices (based on python-architecture example)

## - [ ] Phase 3: Diff Acquisition

Implement the ability to fetch pull request diffs from two sources:

**Technical approach:**
- Implement command-line flag to switch between local and remote diff modes
- **Local mode**: Execute git diff commands against local repository
  - Work with checked-out branches
  - Support full repo access for context
- **Remote mode**: Fetch diffs via GitHub API
  - For now, limit to smaller PRs (workaround: show "PR too large" message for oversized PRs)
  - Future enhancement: fetch old file versions from GitHub API and create custom diffs
- Create common diff interface that produces identical output format regardless of source
- Both modes should produce the same data structure for downstream processing

**Files to create:**
- Python script for local git diff execution
- Python script for GitHub API diff fetching
- Common diff data structure/interface

**Expected outcomes:**
- Diff data is fetched and normalized from either local or remote sources
- Both modes produce consistent output format
- Ready for diff segmentation and chunking

## - [ ] Phase 4: Diff Segmentation and Chunking

Develop the logic to break down diffs into reviewable chunks with intelligent handling of different change types:

**Technical approach:**
- Move away from file-level reviews to **hunk-level reviews**
- Implement "effective diff" creation that enriches raw diff data:
  - Classify each change as: added, deleted, modified, or moved
  - **Moved code detection**: Use similarity heuristics to identify when code appears to have been relocated
    - Search through diff for similar method names/implementations
    - Mark as "moved" rather than "deleted + added"
  - For non-moved changes, process hunk by hunk
- Consider two approaches for method/function context:
  - Option A: Use AI to identify method boundaries (current approach)
  - Option B: Use regex/AST parsing for structured identification (preferred for consistency)
- Create enriched diff format that includes:
  - Change classification (added/deleted/modified/moved)
  - Hunk information
  - Method/function context where applicable
  - Line numbers and file paths

**Important considerations:**
- Handle edge cases: method name changes, method moves, reorganized code
- Maintain enough context for meaningful review without overwhelming the reviewer
- Balance between granularity and context

**Expected outcomes:**
- Diffs are broken into logical, reviewable chunks
- Each chunk has proper classification and context
- Moved code is identified and handled appropriately
- Output artifact file contains structured chunk data for inspection

## - [ ] Phase 5: Rule Management System

Build the system for defining, storing, and applying review rules to code chunks:

**Rule structure:**
- Each rule checks one specific thing (single responsibility)
- Rules include metadata:
  - File type filters (only apply to .py, .js, etc.)
  - Grep patterns (only apply if certain code patterns exist)
  - Description of what the rule checks
  - Severity level
  - Documentation links (optional)
- Rules are stored as external files in a rules directory
- Format should be simple and version-controllable

**Rule application logic:**
- First pass: cheap heuristics to determine rule applicability
  - Use bash/scripting for file type checks
  - Use grep for pattern matching
  - Filter out non-applicable rules before AI analysis
- Create mapping of chunks to applicable rules
- This pre-filtering keeps costs manageable

**Files to create:**
- Rule file format specification
- Rule loader/parser
- Rule applicability checker (heuristics engine)
- Chunk-to-rule mapping generator

**Expected outcomes:**
- Rules can be easily defined and modified
- System efficiently determines which rules apply to which chunks
- Mapping artifact shows exactly which rules will be checked for each chunk

## - [ ] Phase 6: AI Review Execution Engine

Implement the core review logic that applies rules to code chunks using AI agents:

**Technical approach:**
- For each chunk, iterate through applicable rules serially
- **CRITICAL**: Spawn a separate AI subagent for each rule check using `model: "sonnet"` (latest sonnet model)
- **Subagent requirement is mandatory** — do NOT skip subagents regardless of diff size. Even small diffs require dedicated subagent analysis per rule to catch subtle violations. This is non-negotiable.
- Each agent evaluates:
  - Does this rule actually apply? (AI may determine it doesn't after deeper analysis)
  - If applicable, does the code violate the rule?
  - If violated, how severe is the violation? (scoring)
  - What specific feedback should be given?
- Collect results including:
  - Rule ID and description
  - Applies/doesn't apply status
  - Pass/fail status
  - Severity score (for prioritization)
  - Specific feedback/suggestion
  - Code location (file, line numbers)

**Important considerations:**
- Handle large PRs gracefully - may need to limit number of rules or chunks
- Consider timeout handling for long-running checks
- Provide progress indication for user
- Allow for rule composition (simple atomic rules vs complex contextual rules)

**Expected outcomes:**
- Each applicable rule is checked with dedicated AI focus
- Results are structured and scored
- Artifact file contains all raw review results for inspection
- Pipeline can be paused/resumed between chunks

## - [ ] Phase 7: Review Report Generation and Filtering

Create the system that synthesizes individual rule checks into a coherent review report:

**Report structure:**
- Overall PR score/summary
- Violations grouped by severity
- Each violation includes:
  - Rule that was violated
  - Location in code
  - Explanation of the issue
  - Suggested fix
  - Links to documentation (if rule provides them)
- Separate section for code that passed all checks (optional, for transparency)

**Interactive filtering:**
- Tool generates complete review
- Presents violations one by one in console
- User can decide for each violation:
  - Post as GitHub comment
  - Skip (not worth commenting)
  - Edit feedback before posting
- Allows rapid iteration: "here's what I found, you decide what's worth sharing"

**Files to create:**
- Report generator
- Interactive console interface for review approval
- Formatting logic for different output types (console, markdown, etc.)

**Expected outcomes:**
- Clear, actionable review reports
- User maintains control over what feedback is shared
- Reports are professional and include supporting documentation
- Foundation for eventual automation (once rules are proven)

## - [ ] Phase 8: GitHub Integration

Add the ability to post review comments directly to GitHub pull requests:

**Technical approach:**
- Use GitHub API to post review comments
- Support two modes:
  - Individual comments on specific lines
  - Single review with multiple comments
- Include proper formatting (code blocks, links, etc.)
- Handle GitHub API rate limiting
- Support for GitHub Actions integration

**Features:**
- Post comments from filtered review results
- Link comments to specific lines of code
- Include rule documentation links
- Support batch posting (all approved comments at once)
- Dry-run mode to preview what would be posted

**Expected outcomes:**
- Approved feedback can be posted to PRs with one command
- Comments are well-formatted and linked to code
- Foundation for GitHub Actions workflow
- Tool can be used from CI/CD pipelines

## - [ ] Phase 9: Local Iteration and Rule Development

Use the tool on real pull requests to refine rules and gather learnings:

**Activities:**
- Run tool locally on colleague PRs (with permission)
- Review results for false positives
- Refine rule definitions based on learnings
- Add new rules for common issues discovered
- Document patterns and best practices
- Create example rules for common scenarios:
  - Security issues (SQL injection, XSS, etc.)
  - Code style and consistency
  - Performance anti-patterns
  - Testing requirements
  - Documentation completeness
  - API design patterns

**Success criteria:**
- False positive rate is acceptably low (subjective but aim for <20%)
- Rules catch real issues that would be mentioned in manual reviews
- Tool provides value worth the cost (time + API costs)
- Ready to share with team for feedback

**Duration:** Plan for ~2 weeks of daily usage and iteration

**Expected outcomes:**
- Solid set of battle-tested rules
- Confidence in tool's accuracy and value
- Data on cost per PR (actual dollars spent)
- Documentation of common patterns and edge cases

## - [ ] Phase 10: Documentation and Packaging

Prepare the tool for wider distribution:

**Documentation to create:**
- README with overview and value proposition
- Installation and setup guide
- Rule creation tutorial
- Rule file format specification
- Configuration options reference
- Example rules library
- Troubleshooting guide
- Cost estimation guide

**Packaging:**
- Finalize plugin structure
- Include all necessary Python dependencies
- Create simple invocation method
- Provide example configuration
- Set up repository for distribution
- Consider: publish to Claude Code plugin registry (if available)

**Expected outcomes:**
- Tool can be adopted by others with minimal setup
- Clear documentation enables rule creation
- Professional presentation for stakeholder demos
- Ready for team evaluation and feedback

## - [ ] Phase 11: CI/CD Integration (Future)

Once the tool is proven locally, extend it for automated workflows:

**Features:**
- GitHub Actions workflow that runs on new PRs
- Automatic rule checking without manual intervention
- Configurable: can run all rules or subset
- Posts results as PR comments or check results
- Supports different modes:
  - Advisory (comments only, doesn't block)
  - Blocking (requires fixes before merge)
  - Silent (logs only, for observation)
- Cost controls (limit max rules/chunks per PR)

**Important notes:**
- Only implement after tool is proven in Phase 7
- Requires team buy-in and cultural support
- Start with advisory mode to build trust
- Provide escape hatches for urgent merges

**Expected outcomes:**
- Automated reviews on all new PRs
- Consistent feedback across all code changes
- Scales review process beyond individual reviewers
- Frees senior engineers to focus on architectural review

## - [ ] Phase 12: Validation and Testing

Comprehensive validation of the tool across different scenarios:

**Unit tests:**
- Diff fetching (both local and remote)
- Diff chunking and classification
- Rule parsing and loading
- Rule applicability heuristics
- Report generation

**Integration tests:**
- End-to-end flow with sample PRs
- Different PR sizes and complexity levels
- Different programming languages
- Edge cases (moved code, large refactors, etc.)

**Manual validation:**
- Run tool on 10+ real PRs from different developers
- Compare results to manual code review
- Measure false positive and false negative rates
- Gather feedback from PR authors
- Validate cost per PR is acceptable
- Ensure review quality meets or exceeds expectations

**Success criteria:**
- All pipeline phases produce valid artifacts
- False positive rate < 20%
- Finds issues that would be caught in manual review
- Cost per PR is reasonable ($1-5 range)
- Tool completes reviews in reasonable time (<10 minutes for typical PR)
- Documentation is clear and complete

**Expected outcomes:**
- Confidence in tool reliability
- Known limitations are documented
- Ready for production use
- Baseline metrics for future improvements
