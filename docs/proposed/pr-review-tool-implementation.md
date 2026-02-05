# PR Review Tool Implementation Plan

## Background

This plan details the phased implementation of PRRadar. The tool architecture and vision are documented in the main README.md. This document focuses on the technical implementation approach, breaking the work into phases that build on strong foundations.

**Reference:** Bill mentioned checking `~/Developer/personal/` for existing git diff code. The `git-tools` repo has general git operations but not unified diff parsing.

## Phases

# Local Diff and Focus Areas

The following phases add local git diff support and focus area capabilities for reviewing large changes.

## - [ ] Phase 3: Diff Source Abstraction

Create an abstraction layer that allows switching between GitHub API and local git for diff acquisition. Both sources must produce identical hunk format to feed into the same downstream pipeline.

**Tasks:**
- Add `DiffSource` enum to domain: `GITHUB_API`, `LOCAL_GIT`
- Create `DiffProvider` protocol/interface in `services/` with method `get_diff(pr_number) -> str`
- Implement `GitHubDiffProvider` wrapping existing `gh pr diff` logic
- Implement `LocalGitDiffProvider`:
  - Fetch PR metadata to get head branch name
  - Checkout/fetch the PR branch locally (or use worktree)
  - Compute diff against base branch using `git diff <base>...<head>`
  - Return raw unified diff text (same format as GitHub API)
- Update `cmd_diff.py` to accept `--source github|local` flag (default: github)
- Add `--local-repo-path` optional argument (defaults to current directory)
- Both providers must produce identical output format so downstream parsing remains unchanged

**Key consideration:** Local diff requires the repository to be cloned. The tool should detect if running in a valid git repo and fail gracefully with helpful message if not.

**Files to modify:**
- New: `domain/diff_source.py` (enum and provider interface)
- New: `services/diff_provider.py` (implementations)
- Modify: `commands/agent/diff.py` (add --source flag)
- Modify: `infrastructure/gh_runner.py` (extract to provider pattern)

**Expected outcomes:**
- Diff data is fetched and normalized from either local or remote sources
- Both modes produce consistent output format
- Ready for diff segmentation and focus area processing

---

## - [ ] Phase 4: Focus Area Domain Model

Add the `FocusArea` domain model that represents a scoped portion of a hunk for focused review. When reviewing large files (e.g., 1000+ line new files or big changes), instead of reviewing the entire hunk, break it into "focus areas" by method. This keeps reviews scoped and focused.

**Tasks:**
- Create `FocusArea` dataclass in `domain/focus_area.py`:
  ```python
  @dataclass
  class FocusArea:
      start_line: int      # First line of focus (new file line numbers)
      end_line: int        # Last line of focus
      description: str     # E.g., "updateUser method" or "lines 20-45"
      hunk_index: int      # Which hunk this focus belongs to
  ```
- Update `CodeSegment` to include optional `focus_area: FocusArea | None`
- When `focus_area` is present, the segment represents just that portion of the hunk
- Add `CodeSegment.get_focused_content()` method that extracts only the lines within the focus area bounds
- Update `CodeSegment.to_dict()` and `from_dict()` for serialization

**Files to modify:**
- New: `domain/focus_area.py`
- Modify: `domain/evaluation_task.py` (update CodeSegment)

---

## - [ ] Phase 5: Focus Area Generation

Implement Claude-based analysis to break large hunks into method-level focus areas.

**Tasks:**
- Add configuration for "large hunk" threshold (e.g., >100 changed lines)
- Create `services/focus_generator.py` with `FocusGeneratorService`:
  - Input: Hunk content + full file content (when available)
  - Use Claude to analyze and suggest focus area boundaries
  - Heuristics to provide Claude:
    - Break by method/function boundaries
    - Keep related changes together
    - Aim for reviewable chunks (50-150 lines)
  - Output: List of `FocusArea` objects
- **Extensibility:** While method boundaries are the initial chunking strategy, this approach can evolve to support other specialized reviews (e.g., chunking by class, by logical code block, or by architectural concern).
- Create prompt template for Claude that receives:
  - The hunk diff (with line numbers)
  - The full file content (for context on method boundaries)
  - Instructions for breaking into logical chunks
- Add `--generate-focus-areas` flag to `cmd_rules.py` (or make it automatic above threshold)
- When generating evaluation tasks, if focus areas exist:
  - Create one segment per (hunk, focus_area) combination
  - Each segment gets evaluated independently

**Important:** The hunk format stays identical. Focus areas are metadata that tell the evaluator which portion to concentrate on.

**Files to modify:**
- New: `services/focus_generator.py`
- New: `prompts/focus_generation.py` (prompt template)
- Modify: `commands/agent/rules.py` (integrate focus generation)

---

## - [ ] Phase 6: Update Grep Filtering for Focus Areas

Update the rule filtering logic to respect focus area bounds when checking grep patterns.

**Tasks:**
- Modify `rule_loader.filter_rules_for_segment()`:
  - If segment has `focus_area`, extract only lines within focus bounds for grep matching
  - Use `CodeSegment.get_focused_content()` instead of full hunk content
- Update `Hunk.extract_changed_content()` or create variant that accepts line range
- Ensure grep patterns only match against the focused portion, not the entire hunk
- Add tests verifying grep patterns respect focus boundaries

**Rationale:** Currently, grep patterns check the entire hunk. With focus areas, a rule should only match if the pattern exists within the focused lines, not elsewhere in the hunk.

**Files to modify:**
- Modify: `services/rule_loader.py`
- Modify: `domain/diff.py` (line-range extraction)
- Modify: `domain/evaluation_task.py` (get_focused_content implementation)

---

## - [ ] Phase 7: Rule Scope (Localized vs Global)

Add `scope` field to rules to distinguish between localized and global evaluation modes.

**Tasks:**
- Add `RuleScope` enum: `LOCALIZED`, `GLOBAL`
- Add `scope: RuleScope` field to `Rule` dataclass (default: `LOCALIZED`)
- Update `Rule.from_file()` to parse `scope` from frontmatter
- Update `Rule.to_dict()` for serialization
- Document the difference:
  - `LOCALIZED`: Rule can be evaluated per-segment (method-level). Works with focus areas.
  - `GLOBAL`: Rule needs broader context. Should receive full diff or multiple segments together.

**Downstream impact (future phases):**
- Localized rules: Evaluated per segment/focus-area as currently done
- Global rules: Need different evaluation strategy (aggregate segments, provide full diff context)
- For now, just add the field and parse it. Later phases can implement different evaluation paths for global rules.

**Example rule frontmatter:**
```yaml
---
description: Check for proper error handling
category: error-handling
scope: localized  # or 'global' for architectural reviews
applies_to:
  file_patterns: ["*.swift"]
---
```

**Files to modify:**
- Modify: `domain/rule.py` (add RuleScope enum and field)
- Update: `services/rule_loader.py` (if any filtering changes needed)

---

# Core Pipeline Phases

## - [ ] Phase 8: Diff Segmentation and Chunking

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
- Integrate with focus areas when segments are large

**Important considerations:**
- Handle edge cases: method name changes, method moves, reorganized code
- Maintain enough context for meaningful review without overwhelming the reviewer
- Balance between granularity and context

**Expected outcomes:**
- Diffs are broken into logical, reviewable chunks
- Each chunk has proper classification and context
- Moved code is identified and handled appropriately
- Output artifact file contains structured chunk data for inspection

## - [ ] Phase 9: Rule Management System

Build the system for defining, storing, and applying review rules to code chunks:

**Rule structure:**
- Each rule checks one specific thing (single responsibility)
- Rules include metadata:
  - File type filters (only apply to .py, .js, etc.)
  - Grep patterns (only apply if certain code patterns exist)
  - Description of what the rule checks
  - Severity level
  - Documentation links (optional)
  - **Scope** (localized vs global, from Phase 7)
- Rules are stored as external files in a rules directory
- Format should be simple and version-controllable

**Rule application logic:**
- First pass: cheap heuristics to determine rule applicability
  - Use bash/scripting for file type checks
  - Use grep for pattern matching
  - Filter out non-applicable rules before AI analysis
  - Respect focus area bounds when matching (from Phase 6)
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

## - [ ] Phase 10: AI Review Execution Engine

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
- For segments with focus areas, update evaluation prompt to include focus area hint: "Focus your review on lines X-Y"
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

## - [ ] Phase 11: Review Report Generation and Filtering

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

## - [ ] Phase 12: GitHub Integration

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

---

# Polish and Distribution

## - [ ] Phase 13: CLI Integration for Focus Areas

Wire focus area and diff source features together in the CLI for smooth user experience.

**Tasks:**
- Update `agent diff` command:
  - Verify `--source github|local` argument works end-to-end
  - Verify `--local-repo-path` argument works correctly
- Update `agent rules` command:
  - Add `--focus-threshold N` argument (hunks with >N changed lines get focus areas)
  - Add `--no-focus` flag to disable focus area generation
- Update `agent evaluate` command:
  - Handle segments with focus areas (pass focus context to evaluation prompt)
- Update `agent analyze` interactive flow:
  - Show focus area info when prompting user
  - Group tasks by segment+focus for cleaner UX
- Ensure all artifacts (tasks/*.json, evaluations/*.json) include focus area data

**Files to modify:**
- Modify: `commands/agent/diff.py`
- Modify: `commands/agent/rules.py`
- Modify: `commands/agent/evaluate.py`
- Modify: `commands/agent/analyze.py`
- Modify: `services/evaluation_service.py` (prompt updates)

## - [ ] Phase 14: Local Iteration and Rule Development

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

## - [ ] Phase 15: Documentation and Packaging

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

## - [ ] Phase 16: CI/CD Integration (Future)

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
- Only implement after tool is proven in Phase 11
- Requires team buy-in and cultural support
- Start with advisory mode to build trust
- Provide escape hatches for urgent merges

**Expected outcomes:**
- Automated reviews on all new PRs
- Consistent feedback across all code changes
- Scales review process beyond individual reviewers
- Frees senior engineers to focus on architectural review

## - [ ] Phase 17: Validation and Testing

Comprehensive validation of the tool across different scenarios:

**Unit tests:**
- Diff fetching (both local and remote)
- Diff chunking and classification
- Rule parsing and loading
- Rule applicability heuristics
- Report generation
- `DiffProvider` implementations (mock git commands)
- `FocusArea` creation and serialization
- `CodeSegment.get_focused_content()`
- Grep filtering with focus areas
- `Rule` scope parsing

**Integration tests:**
- End-to-end flow with sample PRs
- Different PR sizes and complexity levels
- Different programming languages
- Edge cases (moved code, large refactors, etc.)
- Run `agent diff --source local` on a test PR
- Generate focus areas for a large hunk

**Manual validation:**
- Run tool on 10+ real PRs from different developers
- Compare results to manual code review
- Measure false positive and false negative rates
- Gather feedback from PR authors
- Validate cost per PR is acceptable
- Ensure review quality meets or exceeds expectations
- Run full pipeline on a real PR with large file changes
- Verify focus areas break logically at method boundaries
- Verify grep patterns respect focus bounds
- Test both `--source github` and `--source local` produce same downstream results

**Test files to create:**
- `tests/domain/test_focus_area.py`
- `tests/domain/test_diff_source.py`
- `tests/services/test_diff_provider.py`
- `tests/services/test_focus_generator.py`
- Update existing: `tests/domain/test_rule.py` (scope tests)
- Update existing: `tests/services/test_rule_loader.py` (focus filtering)

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

---

## Open Questions

1. **Local diff checkout strategy:** Should we use `git worktree` for isolation, or checkout in place? Worktrees are cleaner but add complexity.

2. **Focus area generation model:** Which Claude model for focus generation? Haiku for speed/cost since it's structural analysis, or Sonnet for better method boundary detection?

3. **Global rule evaluation strategy:** How should global-scoped rules receive context? Options:
   - Concatenate all segments into one evaluation
   - Provide PR summary + full diff
   - Multiple-pass evaluation
   This is deferred to future work but worth noting.

4. **Full file content acquisition:** For focus generation, we may need the complete new file (not just diff). Should this be fetched from GitHub API or local checkout? Local checkout would make this easier.
