# Code Review Skill Roadmap

## GitHub Action Integration

### Goal

Run the code review skill as a GitHub Action so reviews happen automatically and results are visible in GitHub.

### Planned Improvements

#### 1. Manual Workflow Dispatch (First Step)
- Create a GitHub Action workflow that can be triggered manually
- Output review results to the GitHub Actions job summary
- Allows testing and iteration without affecting PRs directly

#### 2. PR Summary Comments
- Post review summary as a comment on the PR's main conversation view
- Single consolidated comment with violation counts and key findings
- Update existing comment on re-runs instead of creating duplicates

#### 3. Inline PR Comments
- Post violations as inline comments on specific lines in the PR diff
- Requires accurate line number mapping (see GitHub Comments section)
- Most actionable format for developers reviewing the PR

#### 4. Show Cost
- Display AI/token usage cost for each review run
- Helps track and optimize review expenses

### Success Criteria

- [ ] Workflow can be triggered manually via workflow_dispatch
- [ ] Review results appear in GitHub Actions job summary
- [ ] Summary can be posted to PR conversation
- [ ] Inline comments can be posted to PR diff

---

## PR Checkout Strategy

### Goal

Check out the actual PR branch instead of using `gh api` to fetch diffs, ensuring full code context is available during review.

### Rationale

- `gh api` diffs only provide changed lines without surrounding context
- Checking out the repo allows reading full files, understanding imports, and seeing related code
- Rules can reference other parts of the codebase (e.g., checking if a protocol exists, validating naming against existing patterns)
- Enables more accurate architectural analysis by understanding the full dependency graph

### Approach

- Clone/checkout the PR branch in the GitHub Action
- Run the review skill against the local checkout
- Use `git diff` against the base branch to identify changed files/lines
- Read full file contents when applying rules

### Success Criteria

- [ ] GitHub Action checks out PR branch before running review
- [ ] Rules have access to full file contents, not just diffs
- [ ] Review can reference non-changed files for context

---

## Summary Scoring

### Goal

Provide high-level scores for aspects like architecture adherence, giving developers guidance rather than line-level call-outs.

### Rationale

Some review aspects don't fit well as inline comments:
- It's not always clear whether a specific line warrants a comment
- Developers may benefit more from understanding overall patterns than individual violations
- A score provides a softer, more constructive form of feedback

### Planned Improvements

#### 1. Architecture Score
- Score how well the PR adheres to architectural principles
- Consider: layering, dependency direction, abstraction usage, separation of concerns
- Presented in the summary rather than as inline comments

#### 2. Other Potential Scores
- Code complexity score
- Test coverage alignment
- Consistency with existing patterns

### Success Criteria

- [ ] Architecture score is calculated and displayed in review summary
- [ ] Scores provide actionable guidance without being overly prescriptive

---

## Slice Up PR into Smaller Pieces

### Goal

Improve PR segmentation by intelligently identifying logical code units, function signatures, and moved code to produce more meaningful review segments.

### Current Behavior

The skill segments diffs into logical units (methods, interfaces, properties, etc.) based on syntax patterns, but lacks:
- Recognition of function signatures from removed code (old code)
- Detection of moved code (same code appearing as both removed and added elsewhere)

### Planned Improvements

#### 1. Identify Function Signatures (Including from Old Code)
- Parse removed lines (`-`) to extract function/method signatures
- Match removed signatures with added signatures to detect renames or signature changes
- Provide context about what the old function looked like when reviewing the new version

#### 2. Identify Moved Code
- Detect when a block of code is removed from one location and added to another
- Mark these segments as "moved" rather than "removed + added"
- Reduce noise in reviews by not flagging moved code as new violations

#### 3. Script/Tooling
- Consider a preprocessing script to analyze diffs before segmentation
- Output structured data about moves, renames, and signature changes
- Reference: https://github.com/jeppesen-foreflight/ff-ffm-static-analyzer may have reusable code
- Reference: https://github.com/jeppesen-foreflight/ff-ffm-pr-radar may have reusable code

### Success Criteria

- [ ] Moved code is detected and labeled appropriately
- [ ] Function signature changes are identified with before/after context
- [ ] Review noise is reduced for refactoring PRs

---

## Rule Usage Optimization

### Goal

Reduce unnecessary AI usage by pre-filtering which rules apply to which segments, and allow rules to be run selectively.

### Planned Improvements

#### 1. Grep-Based Rule Application
- Before spawning an AI agent to review a segment, use grep to check if the rule is relevant
- Example: Skip "nullability" rule if segment contains no Objective-C property declarations
- Example: Skip "error-handling" rule if segment contains no async/await or throwing code
- Saves AI calls for segments where a rule clearly doesn't apply

#### 2. Flexible Rules
- Not all rules need to run every time
- Allow rules to be categorized (e.g., "always", "on-demand", "code-smells")
- Example: "code smells" rules might only run when explicitly requested
- Add frontmatter field like `run_mode: always | on_demand | manual`

#### 3. Rule Confidence Scores
- Add a confidence score to rules indicating how reliable the rule's flagging is
- Important for weaker rules (e.g., "default fallbacks") where violations may be acceptable
- Helps prioritize which violations to address first

### Success Criteria

- [ ] Rules can specify grep patterns that must match before the rule runs
- [ ] Rules can be categorized by run mode
- [ ] Rules can define confidence levels
- [ ] AI usage is reduced for irrelevant rule/segment combinations

---

## GitHub Comments

### Goal

Improve the workflow for posting review violations as comments to GitHub PRs and notifying via Slack.

### Planned Improvements

#### 1. Line Number Derivation
- Accurately map violation locations to PR diff line numbers
- GitHub PR comments require diff-relative line numbers, not file line numbers
- Script or logic to translate segment positions to correct diff lines

#### 2. Comment Templates in Frontmatter
- Allow rules to define GitHub comment templates in their frontmatter
- Standardize comment format across rules
- Include links to documentation, suggested fixes, code examples

#### 3. Slack Notifications
- Script to post review summaries to Slack
- Link to PR and highlight key violations
- Configurable channel/thread targeting

### Success Criteria

- [ ] Violations are posted to correct line numbers in PR diffs
- [ ] Rules can define custom comment templates
- [ ] Slack summary notifications are supported

---

## Rule Organization

Rules are organized by concern to avoid overlap (alphabetical):

### APIs: Apple
Correct usage of Apple-provided APIs and frameworks.

- ObjC Collections generics (NSArray, NSDictionary type annotations)
- Nullability annotations (missing annotations can cause crashes)
- ObjC property access patterns
- Localization (NSLocalizedString, String Catalogs)
- Unnecessary Swift case values (e.g., `case unknown = 0`)
- Using static variables for mutually exclusive states (instead of enum)
- Risky APIs (`objc_getAssociatedObject`)
- Import order

### APIs: FFM
Correct usage of ForeFlight-specific APIs and patterns.

- Service locator usage (prefer dependency injection)

### Architecture
Design patterns, layering, and structural concerns.

- Plugin architecture violations (higher level classes should use abstractions)
- Logic in wrong layer (putting logic in lower layers helps define it with a name)
- Weak client contracts (accepting nil but treating as invalid)
- Excessive casting / `isKindOfClass` usage

### Clarity & Correctness
Code path clarity and readability.

- Guard clause misuse (returning nil at end of method is a sign)
- Unclear flow / hard-to-follow logic
- Missing intermediate local variables for complex conditionals
- Poor naming (e.g., `temp` variables)