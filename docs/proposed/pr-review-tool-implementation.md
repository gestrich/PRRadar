# PR Review Tool Implementation Plan

## Background

This plan details the phased implementation of PRRadar. The tool architecture and vision are documented in the main README.md. This document focuses on the technical implementation approach, breaking the work into phases that build on strong foundations.

**Reference:** Bill mentioned checking `~/Developer/personal/` for existing git diff code. The `git-tools` repo has general git operations but not unified diff parsing.

## Phases

# Local Diff and Focus Areas

The following phases add local git diff support and focus area capabilities for reviewing large changes.

## - [ ] Phase 1: Diff Source Abstraction

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

## - [ ] Phase 2: Focus Area Domain Model

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

## - [ ] Phase 3: Focus Area Generation

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

## - [ ] Phase 4: Update Grep Filtering for Focus Areas

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

## - [ ] Phase 5: Rule Scope (Localized vs Global)

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

# Polish and Distribution

## - [ ] Phase 6: CLI Integration for Focus Areas

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

## - [ ] Phase 7: Local Iteration and Rule Development

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

## - [ ] Phase 8: Documentation and Packaging

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

## - [ ] Phase 9: CI/CD Integration (Future)

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
