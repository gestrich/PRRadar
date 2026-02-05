# Reviewing PR Diffs

Instructions for retrieving and analyzing pull request diffs using the `gh` CLI.

## Input Detection

Identify PR input by one of these formats:
- **PR link**: Contains `github.com` and `/pull/` (e.g., `https://github.com/owner/repo/pull/123`)
- **PR number with hash**: Starts with `#` (e.g., `#123`)
- **Plain PR number**: Numeric value (e.g., `123`)

## Extract PR Number

```
From URL:       https://github.com/owner/repo/pull/123 → 123
From #format:   #123 → 123
From number:    123 → 123
```

## Commands

### 1. Get PR Metadata

```bash
gh pr view <number> --json title,body,baseRefName,headRefName
```

Returns:
- `title`: PR title for the review summary header
- `body`: PR description for context
- `baseRefName`: Target branch (e.g., `main`)
- `headRefName`: Source branch with changes

### 2. Get the Diff

```bash
gh pr diff <number>
```

**IMPORTANT**: Save this diff content — you will need to pass it to subagents. The changed files may not exist locally; they only exist in the PR diff.

### 3. List Changed Files

```bash
gh pr view <number> --json files --jq '.files[].path'
```

Returns a list of file paths that changed in the PR.

## Output File Naming

The review summary file should be named:
```
review-summary-<pr_number>.md
```

Example: `review-summary-18500.md`

## Workflow

1. Extract the PR number from input
2. Run `gh pr view` to get PR metadata (title, body, branches)
3. Run `gh pr diff` to get the full diff — **save this for subagents**
4. Run `gh pr view --json files` to list changed files
5. Segment each file's diff into logical code units (see [code-segmentation.md](code-segmentation.md))
6. Generate `review-summary-<pr_number>.md` with segments organized by file
