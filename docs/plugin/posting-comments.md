# Posting Review Comments to GitHub

This document describes how to post code review violations as comments on a GitHub PR.

## When to Use

Use this workflow when:
- The user asks to "post comments" or "post review" to GitHub
- The user wants to submit feedback from a completed code review
- The user says "post to PR" or "submit comments"

## Prerequisites

- A completed code review with a `review-summary-<id>.md` file
- The review must be for a PR (not a commit SHA)
- The `gh` CLI must be authenticated

## Comment Format

For each violation (score > 5), format the comment as follows:

```
<explanation of the issue>

<recommended fix with code snippet if applicable>

See: <documentation_link>
```

### Example Comment

```
This property needs a nullability annotation since it's an object pointer. Given that it's set to `nil` after use, it should be `nullable`:

@property (nullable) UIActivityIndicatorView *loadingSpinner;

See: <documentation_link>
```

## Interactive Workflow

Process violations one at a time:

1. **Present the comment** to the user with:
   - File name
   - Line number
   - The formatted comment text (ready to copy or post)

2. **Ask for approval** using AskUserQuestion:
   - "Post this comment" - Post and continue to next
   - "Skip" - Skip this comment, continue to next
   - "Stop" - End the posting workflow

3. **If approved**, post the inline comment using the reviews API (see gh CLI Commands section)

4. **Continue** to the next violation until all are processed or user stops

## Output Format for Each Violation

Present each violation to the user in this format:

```
**File:** `<filename>`
**Line:** <line_number>

**Comment:**
```
<the comment text to post>
```
```

## Extracting Violations from Summary

Parse the `review-summary-<id>.md` file to find violations:

1. Look for rule review lines with `Score: N` where N > 5
2. Extract:
   - File path from the `## File:` header
   - Line number from `Line: N` in the review line
   - Rule name from the `**rule-name**` in the review line
   - Details from `Details: ...`
3. Read the rule file to get:
   - The `documentation` link from frontmatter
   - The `## GitHub Comment` section which provides a template for formatting the comment

## gh CLI Commands

### Post a general review comment (appears in PR conversation)
```bash
gh pr review <pr_number> --comment --body "comment text"
```

### Post an inline comment on a specific line
Use the reviews API with JSON input to post inline comments:

```bash
# First, get the commit SHA
COMMIT_SHA=$(gh pr view <pr_number> --json headRefOid --jq '.headRefOid')

# Then post the inline comment
cat << 'EOF' | gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews --method POST --input -
{
  "commit_id": "<commit_sha>",
  "event": "COMMENT",
  "body": "",
  "comments": [
    {
      "path": "path/to/file.m",
      "line": 63,
      "side": "RIGHT",
      "body": "Your comment here"
    }
  ]
}
EOF
```

### Get the commit SHA for the PR head
```bash
gh pr view <pr_number> --json headRefOid --jq '.headRefOid'
```

## Complete Example

Given a violation:
- File: `ProcedurePreviewViewController.m`
- Line: 63
- Rule: `nullability/nullability_m_files`
- Score: 8
- Details: Missing nullability annotation on `loadingSpinner` property

Present to user:

```
**File:** `ProcedurePreviewViewController.m`
**Line:** 63

**Comment:**
```
This property needs a nullability annotation since it's an object pointer. Given that it's set to `nil` after use, it should be `nullable`:

@property (nullable) UIActivityIndicatorView *loadingSpinner;

See: <documentation_link>
```
```

Then ask:
> Post this comment to PR #18615?
> - Post this comment
> - Skip
> - Stop posting

If approved, run:
```bash
cat << 'EOF' | gh api repos/{owner}/{repo}/pulls/18615/reviews --method POST --input -
{
  "commit_id": "fd7529af6bbe50e0223451020a62db91d8156417",
  "event": "COMMENT",
  "body": "",
  "comments": [
    {
      "path": "src/MyViewController.m",
      "line": 63,
      "side": "RIGHT",
      "body": "This property should have a nullability annotation. Given that it's set to `nil` after use, it should be `nullable`:\n\n```objective-c\n@property (nullable) UIActivityIndicatorView *loadingSpinner;\n```\n\nSee [Documentation for Nullability](<documentation_link>)"
    }
  ]
}
EOF
```
