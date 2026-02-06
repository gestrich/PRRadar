# Focus Areas Implementation Plan

## Background

Focus areas allow PRRadar to identify and review changes at the method level rather than at the hunk level. Every method that is added, modified, or removed gets its own focus area for targeted evaluation.

This approach:
- Provides method-level granularity for all changes
- Keeps reviews scoped and manageable
- Allows rules to target specific methods
- Enables more precise rule matching via grep patterns
- Makes it clear which specific methods triggered which rules

**Key principle:** Focus areas are metadata that guide evaluation. The underlying hunk format remains unchanged. Every changed method becomes a separate reviewable unit.

## Phases

## - [ ] Phase 1: Focus Area Domain Model

Add the `FocusArea` domain model that represents a method-level portion of a hunk. Each method that is added, modified, or removed in a hunk gets its own focus area for targeted review.

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

## - [ ] Phase 2: Focus Area Generation

Implement Claude-based analysis to identify all methods that are added, modified, or removed in each hunk.

**Tasks:**
- Create `services/focus_generator.py` with `FocusGeneratorService`:
  - Input: Hunk content + full file content (when available)
  - Use Claude to identify all methods that appear in the diff
  - For each identified method:
    - Determine boundaries (start/end line)
    - Extract method name/signature for description
    - Classify as added, modified, or removed
  - Output: List of `FocusArea` objects (one per method)
- **Extensibility:** While method-level focus is the primary strategy, this approach can evolve to support other granularities (e.g., class-level, property-level, or architectural concern-level).
- Create prompt template for Claude that receives:
  - The hunk diff (with line numbers)
  - The full file content (for context on method boundaries)
  - Instructions for identifying all changed methods
- Focus areas are generated automatically for all hunks during the rules phase
- When generating evaluation tasks:
  - Create one segment per (hunk, focus_area) combination
  - Each segment gets evaluated independently

**Important:** The hunk format stays identical. Focus areas are metadata that tell the evaluator which method to concentrate on.

**Files to modify:**
- New: `services/focus_generator.py`
- New: `prompts/focus_generation.py` (prompt template)
- Modify: `commands/agent/rules.py` (integrate focus generation)

---

## - [ ] Phase 3: Update Grep Filtering for Focus Areas

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

## - [ ] Phase 4: Rule Scope (Localized vs Global)

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

## - [ ] Phase 5: CLI Integration for Focus Areas

Wire focus area generation into the CLI workflow. Focus areas are generated automatically for all hunks.

**Tasks:**
- Update `agent rules` command:
  - Automatically generate focus areas for all hunks after loading diff
  - Show focus area count in output (e.g., "Found 12 methods across 5 hunks")
- Update `agent evaluate` command:
  - Handle segments with focus areas (pass method-level context to evaluation prompt)
  - Display which method is being evaluated in progress output
- Update `agent analyze` interactive flow:
  - Show focus area info (method name) when prompting user
  - Group tasks by file → method for cleaner UX
- Ensure all artifacts (tasks/*.json, evaluations/*.json) include focus area data
- Update report generation to show results grouped by method

**Files to modify:**
- Modify: `commands/agent/rules.py`
- Modify: `commands/agent/evaluate.py`
- Modify: `commands/agent/analyze.py`
- Modify: `services/evaluation_service.py` (prompt updates)
- Modify: `commands/agent/report.py` (method-level grouping)

---

## Open Questions

1. **Focus area generation model:** Which Claude model for identifying methods in diffs? Haiku for speed/cost since it's structural analysis, or Sonnet for better method boundary detection? Consider using Haiku first and upgrading if accuracy is insufficient.

2. **Global rule evaluation strategy:** How should global-scoped rules receive context? Options:
   - Concatenate all method-level segments into one evaluation
   - Provide PR summary + full diff
   - Multiple-pass evaluation (method-level then file-level)
   This is deferred to future work but worth noting.

3. **Full file content acquisition:** For accurate method boundary detection, we need the complete new file (not just diff context lines). Should this be fetched from GitHub API or local checkout? Local checkout would make this easier (see [diff-source-abstraction.md](diff-source-abstraction.md)).

4. **Method identification accuracy:** How should the system handle edge cases like:
   - Partial method changes (only middle of method changed)
   - Multiple methods in one hunk
   - Language-specific method definitions (functions, methods, closures, etc.)
   Consider language-specific heuristics vs universal Claude-based detection.
