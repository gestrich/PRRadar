# Refactor Code Review Skill

## Architecture Overview

```
┌───────────────────────────────────────────────┐
│              TRIGGER SOURCES                  │
├─────────────────────┬─────────────────────────┤
│   Label/Dispatch    │     @code-review        │
│   (review.yml)      │     (mention.yml)       │
└──────────┬──────────┴───────────┬─────────────┘
           │                      │
           │                      ▼
           │              ┌───────────────┐
           │              │ Claude Code   │
           │              │ + interpret-  │
           │              │   request.md  │
           │              │               │
           │              │ Output:       │
           │              │ - action      │
           │              └───────┬───────┘
           │                      │
           │         ┌────────────┴────────────┐
           │         │                         │
           │         ▼                         ▼
           │  ┌─────────────┐          ┌─────────────┐
           │  │ post/reply/ │          │performReview│
           │  │ replace     │          └──────┬──────┘
           │  └──────┬──────┘                 │
           │         │                        │
           │         ▼                        │
           │  ┌─────────────┐                 │
           │  │ Python:     │                 │
           │  │ handle_     │                 │
           │  │ comment_    │                 │
           │  │ action.py   │                 │
           │  └──────┬──────┘                 │
           │         │                        │
           │         │         ┌──────────────┘
           │         │         │
           ▼         │         ▼
    ┌─────────────────────────────────┐
    │ Claude Code + SKILL.md          │
    │                                 │
    │ Output: feedback[], summary{}   │
    └────────────────┬────────────────┘
                     │
                     ▼
    ┌─────────────────────────────────┐
    │ Python: post_review_comments.py │
    │ (posts if score >= 5)           │
    └────────────────┬────────────────┘
                     │
           ┌─────────┴─────────┐
           │                   │
           ▼                   ▼
    ┌─────────────────────────────────┐
    │       GitHub PR Comments        │
    └─────────────────────────────────┘

┌─────────────────────────────────────────┐
│           SKILL FILES                   │
├─────────────────────────────────────────┤
│ SKILL.md          Core review logic     │
│ reviewing-pr-     PR diff via gh CLI    │
│   diff.md                               │
│ reviewing-local-  Commit diff via git   │
│   diff.md                               │
│ code-             Segment diff into     │
│   segmentation.md   logical units       │
│ interpret-        Parse @mention intent │
│   request.md                            │
│ rules/            Review rules          │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│           PYTHON SCRIPTS                │
├─────────────────────────────────────────┤
│ post_review_comments.py                 │
│   - Parse review JSON                   │
│   - Post violations (score >= 5)        │
│                                         │
│ handle_comment_action.py                │
│   - Parse action JSON                   │
│   - post/reply/replace comments         │
└─────────────────────────────────────────┘
```

## Background

The code-review skill currently mixes two concerns:
1. **Core review logic** - Analyzing diffs, segmenting code, running rules, generating summaries
2. **GitHub interaction** - Responding to `@code-review` mentions and posting violations as PR comments

This refactor separates these concerns so SKILL.md focuses purely on performing code reviews. The GitHub interaction features will be handled elsewhere (details to come in later phases).

The skill should still support:
- Reviewing PRs (by link or number)
- Reviewing commits (by SHA)
- Filtering reviews by specific files or specific rules

---

## Phases

- [x] Phase 1: Refactor SKILL.md to focus on code review only

### Technical Notes

Completed on 2025-02-01. Changes made:
1. Removed "GitHub @code-review Mentions" section (was lines 66-68)
2. Removed "Posting Comments to GitHub" section (was lines 70-72)
3. Removed "GitHub Comment Section" from rule documentation (was lines 255-261)
4. Updated skill description in frontmatter to remove "posting review comments to GitHub"

Files `github-request.md` and `posting-comments.md` still exist and should be removed in Phase 4 as planned.

### Changes to Make

**Remove these sections from SKILL.md:**

1. **Lines 66-68** - Remove "GitHub @code-review Mentions" section:
   ```markdown
   ### GitHub @code-review Mentions
   Users can mention `@code-review` in PR comments to trigger a review...
   ```

2. **Lines 70-72** - Remove "Posting Comments to GitHub" section:
   ```markdown
   ### Posting Comments to GitHub
   After completing a review, you can post violations as comments...
   ```

3. **Lines 255-261** - Remove "GitHub Comment Section" from rule documentation:
   ```markdown
   ### GitHub Comment Section
   Rules can include a `## GitHub Comment` section that provides a template...
   ```

**Keep these capabilities:**

1. Input detection (PR link, PR number, commit SHA)
2. Diff retrieval and file listing
3. Code segmentation logic
4. Review execution with subagents
5. Summary generation
6. Rule matching (including `applies_to.file_extensions`)

**Add/clarify these capabilities:**

1. **Filtering by specific files** - Support reviewing only specific files from the diff
   - Example: `/code-review #123 --files src/auth/*.swift`

2. **Filtering by specific rules** - Support running only specific rules
   - Example: `/code-review #123 --rules nullability,import-order`

### Files to Modify

- `.claude/skills/code-review/SKILL.md` - Main refactor target

### Files to Potentially Remove (confirm in later phase)

- `.claude/skills/code-review/github-request.md` - No longer referenced
- `.claude/skills/code-review/posting-comments.md` - No longer referenced

---

- [x] Phase 2: Extract diff retrieval and segmentation into separate files

### Technical Notes

Completed on 2026-02-01. Changes made:

1. Created `reviewing-pr-diff.md` with:
   - Input detection for PR links, #numbers, and plain numbers
   - PR number extraction examples
   - `gh` CLI commands for metadata, diff, and file list
   - Output file naming convention

2. Created `reviewing-local-diff.md` with:
   - Input detection for commit SHAs
   - `git` commands for commit range, stats, and full diff
   - Commit range syntax explanation
   - Output file naming convention

3. Created `code-segmentation.md` with:
   - Segment types table (imports, interface, extension, properties, method, etc.)
   - Change status definitions (added, removed, modified)
   - Segmentation rules (method boundaries, contiguous changes, context preservation)
   - Examples for Swift, Objective-C, and config files
   - Segment naming conventions

4. Updated SKILL.md:
   - Replaced detailed "Code Segmentation" section with reference to `code-segmentation.md`
   - Replaced "When invoked with a PR link or number" section with reference to `reviewing-pr-diff.md`
   - Replaced "When invoked with a commit SHA" section with reference to `reviewing-local-diff.md`
   - Added "Segmenting the Diff" and "Executing the Review" sections for clarity

Files created:
- `.claude/skills/code-review/reviewing-pr-diff.md`
- `.claude/skills/code-review/reviewing-local-diff.md`
- `.claude/skills/code-review/code-segmentation.md`

---

- [x] Phase 3: Rich JSON schema and Python comment poster

### Technical Notes

Completed on 2026-02-01. Changes made:

1. Created `scripts/post_review_comments.py` with:
   - Dataclass models: `Feedback`, `CategorySummary`, `ReviewSummary`, `ReviewOutput`
   - JSON parsing functions that extract structured output from Claude's execution file format
   - `post_review_comment()` function that posts violations as PR review comments via `gh api`
   - `post_summary_comment()` function that posts a summary comment with category scores
   - CLI interface with `--execution-file`, `--pr-number`, `--repo`, `--min-score`, `--post-summary`, `--dry-run` options

2. Updated `.github/workflows/claude-code-review.yml`:
   - Replaced simple schema with rich JSON schema including `feedback[]`, `summary{}` with categories
   - Updated prompt to instruct Claude on the rich JSON output format
   - Updated parse-output step to use new field paths (`summary.summaryFile`)
   - Added `setup-python@v5` step for Python 3.11
   - Added "Post review comments" step that runs the Python script
   - Changed permissions to `pull-requests: write` and `issues: write` for posting comments

3. Updated `.claude/skills/code-review/SKILL.md`:
   - Added "Structured Output Format (GitHub Actions)" section with JSON schema example
   - Documented feedback array requirements (score >= 5 only)
   - Documented summary categories structure and aggregateScore meaning

### Overview

Enhance the GitHub workflow to:
1. Define a richer JSON schema for Claude's structured output
2. Create a Python script that parses the output and posts PR comments via `gh api`

This separates concerns: Claude focuses on review analysis, Python handles GitHub interaction.

### JSON Schema Design

```json
{
  "success": true,
  "feedback": [
    {
      "file": "src/MyService.swift",
      "segment": "Method fetchUserData()",
      "rule": "error-handling",
      "score": 8,
      "lineNumber": 42,
      "githubComment": "Missing error handling for network timeout. Consider wrapping in do/catch.",
      "details": "The async network call has no error handling..."
    }
  ],
  "summary": {
    "summaryFile": "review-output/review-summary.md",
    "totalSegments": 12,
    "totalViolations": 3,
    "categories": {
      "architecture": {
        "aggregateScore": 7,
        "summary": "Weak client contracts found in 2 files"
      },
      "apis-apple": {
        "aggregateScore": 4,
        "summary": "Minor nullability issues in header files"
      },
      "clarity": {
        "aggregateScore": 2,
        "summary": "Code follows clarity guidelines well"
      }
    }
  }
}
```

### Python Script: `scripts/post_review_comments.py`

**Input:** JSON from Claude's structured output (via file path or stdin)

**Behavior:**
1. Parse JSON into typed dataclasses/Pydantic models
2. Filter feedback items where `score >= 5`
3. For each violation, post a PR review comment using `gh api`:
   ```bash
   gh api repos/{owner}/{repo}/pulls/{pr}/comments \
     -f body="..." -f path="..." -f line=...
   ```
4. Optionally post a summary comment with category scores

**Model Structure:**
```python
@dataclass
class Feedback:
    file: str
    segment: str
    rule: str
    score: int
    line_number: int
    github_comment: str
    details: str

@dataclass
class CategorySummary:
    aggregate_score: int
    summary: str

@dataclass
class ReviewSummary:
    summary_file: str
    total_segments: int
    total_violations: int
    categories: dict[str, CategorySummary]

@dataclass
class ReviewOutput:
    success: bool
    feedback: list[Feedback]
    summary: ReviewSummary
```

### Workflow Changes: `claude-code-review.yml`

1. Update `REVIEW_SCHEMA` env var with the rich schema
2. Add step to run Python script after Claude completes:
   ```yaml
   - name: Post review comments
     if: steps.claude-review.outputs.execution_file != ''
     run: |
       python scripts/post_review_comments.py \
         --execution-file "${{ steps.claude-review.outputs.execution_file }}" \
         --pr-number "${{ github.event.pull_request.number }}" \
         --repo "${{ github.repository }}"
   ```
3. Update SKILL.md instructions to output the rich JSON format

### Files to Create

- `scripts/post_review_comments.py` - Python script for posting comments

### Files to Modify

- `.github/workflows/claude-code-review.yml` - Add rich schema and Python step
- `.claude/skills/code-review/SKILL.md` - Update output format instructions

---

- [ ] Phase 4: Comment workflow with action-based routing

### Overview

Refactor the `@code-review` mention workflow to use a two-step approach:
1. **Claude interprets** the comment and returns structured JSON indicating what action to take
2. **Python/workflow handles** the action (post comment, reply, or trigger review)

This cleanly separates intent recognition (Claude) from execution (Python/workflow).

### Action Schema

Claude returns JSON with an `action` field and action-specific details:

```json
{
  "action": "postComment | replyToComment | replaceComment | postSummary | performReview",
  "...action-specific fields..."
}
```

#### Action: `postComment`
Post a new comment on the PR.
```json
{
  "action": "postComment",
  "body": "Thanks for the question! Here's how the nullability rule works..."
}
```

#### Action: `replyToComment`
Reply to a specific existing comment.
```json
{
  "action": "replyToComment",
  "commentId": 123456789,
  "body": "Good catch! I'll re-review that section..."
}
```

#### Action: `replaceComment`
Edit/replace an existing comment.
```json
{
  "action": "replaceComment",
  "commentId": 123456789,
  "body": "Updated review based on new commits..."
}
```

#### Action: `postSummary`
Post a summary comment (e.g., after answering a question).
```json
{
  "action": "postSummary",
  "body": "## Summary\n\nHere's what the code-review rules check for..."
}
```

#### Action: `performReview`
Trigger a full code review, optionally with additional instructions.
```json
{
  "action": "performReview",
  "additionalInstructions": "Focus only on the nullability rule for header files",
  "filterFiles": ["*.h"],
  "filterRules": ["nullability-h-objc"]
}
```

### Workflow Structure: `claude-code-review-mention.yml`

```yaml
jobs:
  interpret-request:
    # Step 1: Claude interprets the comment
    steps:
      - name: Interpret comment request
        id: interpret
        uses: anthropics/claude-code-action@v1
        with:
          prompt: |
            Analyze this @code-review mention and determine the appropriate action...
          claude_args: --json-schema ${{ env.ACTION_SCHEMA }}

  handle-action:
    needs: interpret-request
    steps:
      # For non-review actions: Python handles GitHub interaction
      - name: Handle comment action
        if: steps.interpret.outputs.action != 'performReview'
        run: |
          python scripts/handle_comment_action.py \
            --action-file "${{ steps.interpret.outputs.execution_file }}" \
            --pr-number "${{ github.event.issue.number }}" \
            --repo "${{ github.repository }}"

      # For performReview: Call the review workflow
      - name: Trigger review workflow
        if: steps.interpret.outputs.action == 'performReview'
        uses: ./.github/workflows/claude-code-review.yml
        with:
          pr_number: ${{ github.event.issue.number }}
          additional_instructions: ${{ steps.interpret.outputs.additionalInstructions }}
```

### Python Script: `scripts/handle_comment_action.py`

**Input:** JSON action from Claude's structured output

**Behavior:**
1. Parse action JSON into typed model
2. Based on `action` field, call appropriate `gh api` command:
   - `postComment` → `gh api repos/{owner}/{repo}/issues/{pr}/comments -f body="..."`
   - `replyToComment` → `gh api repos/{owner}/{repo}/pulls/comments/{id}/replies -f body="..."`
   - `replaceComment` → `gh api repos/{owner}/{repo}/issues/comments/{id} -X PATCH -f body="..."`
   - `postSummary` → Same as postComment but with summary formatting

**Model Structure:**
```python
@dataclass
class PostCommentAction:
    action: Literal["postComment"]
    body: str

@dataclass
class ReplyToCommentAction:
    action: Literal["replyToComment"]
    comment_id: int
    body: str

@dataclass
class ReplaceCommentAction:
    action: Literal["replaceComment"]
    comment_id: int
    body: str

@dataclass
class PostSummaryAction:
    action: Literal["postSummary"]
    body: str

@dataclass
class PerformReviewAction:
    action: Literal["performReview"]
    additional_instructions: str | None
    filter_files: list[str] | None
    filter_rules: list[str] | None

CommentAction = PostCommentAction | ReplyToCommentAction | ReplaceCommentAction | PostSummaryAction | PerformReviewAction
```

### Files to Create

- `scripts/handle_comment_action.py` - Python script for handling comment actions
- `.claude/skills/code-review/interpret-request.md` - Instructions for Claude to interpret `@code-review` mentions (replaces `github-request.md`)

### Files to Modify

- `.github/workflows/claude-code-review-mention.yml` - Two-step action-based flow
- `.github/workflows/claude-code-review.yml` - Accept `additional_instructions` input

### Files to Remove

- `.claude/skills/code-review/github-request.md` - Replaced by `interpret-request.md`
- `.claude/skills/code-review/posting-comments.md` - Functionality moved to Python

---

- [ ] Phase 5: Validation - Create test PR with violation

### Overview

Create a real PR containing code with a single, clear rule violation. The PR should look like normal code changes—do not mention or hint that it contains a violation. This ensures the review system is tested without context pollution.

### Test PR Setup

1. Create a new branch: `test/validation-review-<timestamp>`
2. Add a file with code that violates one of the rules (e.g., missing nullability annotation in `.h` file)
3. Create PR with a neutral title/description (e.g., "Add helper utility class")
4. Record the PR number for subsequent validation phases

### Example Test Code

```objective-c
// FFTestHelper.h - Missing explicit nullability (violates nullability-h-objc)
@interface FFTestHelper : NSObject
@property (nonatomic, strong) NSString *name;  // No nullability
- (NSArray *)items;  // No nullability
@end
```

### Verification

- PR is created successfully
- No review has run yet (baseline state)

---

- [ ] Phase 6: Validation - Review workflow and artifacts

### Overview

Trigger the review workflow on the test PR and verify it produces correct artifacts.

### Steps

1. Add the `claude_review` label to trigger the workflow
2. Wait for workflow to complete using `gh run list` and `gh run watch`
3. Verify workflow completed successfully

### Artifact Verification

Use `gh api` and `gh run download` to verify:

```bash
# List workflow runs for the PR
gh run list --workflow=claude-code-review.yml

# Download artifacts
gh run download <run_id> -n code-review-pr-<pr_number>

# Verify artifact contents
cat review-output/review-summary.md
```

**Expected Results:**
- [ ] Workflow status is "success"
- [ ] Artifact `code-review-pr-<pr_number>` exists
- [ ] `review-summary.md` contains the test file
- [ ] At least one feedback item has `score >= 5`
- [ ] Feedback identifies the nullability violation
- [ ] Summary includes violation count > 0

### JSON Output Verification

Parse the structured output to verify:
- [ ] `success: true`
- [ ] `feedback[]` contains entry for test file
- [ ] `summary.totalViolations >= 1`
- [ ] `summary.categories` has non-zero scores

---

- [ ] Phase 7: Validation - Comment posting

### Overview

Verify that the Python script correctly posts review comments to the PR.

### Steps

1. After Phase 6 workflow completes, check PR comments via API
2. Verify comments are posted for violations (score >= 5)

### Comment Verification

```bash
# List PR comments
gh api repos/{owner}/{repo}/pulls/{pr}/comments

# List issue comments (general PR comments)
gh api repos/{owner}/{repo}/issues/{pr}/comments
```

**Expected Results:**
- [ ] At least one review comment exists on the PR
- [ ] Comment references the violated rule
- [ ] Comment includes file path and line number
- [ ] Comment body matches expected format from rule's template

---

- [ ] Phase 8: Validation - @mention routing and actions

### Overview

Test the `@code-review` mention workflow and verify action routing works correctly.

### Test Cases

**Test 8a: performReview action**
1. Post comment: `@code-review please review this PR`
2. Wait for workflow to complete
3. Verify it triggers a full review (same as Phase 6)

**Test 8b: postComment action (question)**
1. Post comment: `@code-review what does the nullability rule check for?`
2. Wait for workflow to complete
3. Verify a response comment is posted (not a full review)

**Test 8c: replyToComment action**
1. Find an existing review comment ID
2. Post: `@code-review can you explain this violation more?`
3. Verify reply is posted to the correct comment thread

### Verification via API

```bash
# Get comment count before
BEFORE=$(gh api repos/{owner}/{repo}/issues/{pr}/comments | jq length)

# Post @code-review comment
gh api repos/{owner}/{repo}/issues/{pr}/comments \
  -f body="@code-review what rules are available?"

# Wait for workflow
gh run list --workflow=claude-code-review-mention.yml --json status,conclusion

# Get comment count after
AFTER=$(gh api repos/{owner}/{repo}/issues/{pr}/comments | jq length)

# Verify new comment was posted
[ "$AFTER" -gt "$BEFORE" ]
```

**Expected Results:**
- [ ] `performReview` triggers full review workflow
- [ ] Question comments get direct responses (not full reviews)
- [ ] Reply actions post to correct comment threads
- [ ] All actions result in appropriate GitHub API calls

---

- [ ] Phase 9: Validation - Cleanup and summary

### Overview

Clean up test resources and document validation results.

### Cleanup Steps

1. Close the test PR (don't merge)
2. Delete the test branch
3. Optionally delete workflow run artifacts

```bash
# Close PR without merging
gh pr close <pr_number>

# Delete branch
git push origin --delete test/validation-review-<timestamp>
```

### Validation Summary Checklist

Document results for each validation:

| Phase | Check | Status |
|-------|-------|--------|
| 6 | Workflow completes successfully | |
| 6 | Artifacts uploaded | |
| 6 | Review summary contains violation | |
| 6 | JSON output is valid | |
| 7 | Comments posted to PR | |
| 7 | Comments have correct format | |
| 8a | performReview triggers review | |
| 8b | Questions get responses | |
| 8c | Replies post to threads | |

### Success Criteria

All validation phases pass:
- Review workflow detects violations correctly
- Artifacts are generated and uploaded
- Python scripts post comments via `gh api`
- @mention routing works for all action types
- No false positives or missed violations in test case
