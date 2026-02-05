# Reviewing Local Diffs

Instructions for retrieving and analyzing commit diffs using `git` commands.

## Input Detection

Identify commit input as an alphanumeric string that is not a PR link or number:
- **Short SHA**: 7+ character alphanumeric (e.g., `abc1234`)
- **Full SHA**: 40-character alphanumeric

## Commands

### 1. List Commits in Range

```bash
git log --oneline <commit>^..HEAD
```

Shows all commits from the specified commit through HEAD, giving context for the review.

### 2. Get File Change Summary

```bash
git diff <commit>^..HEAD --stat
```

Returns a high-level view of which files changed and how many lines were added/removed.

### 3. Get the Full Diff

```bash
git diff <commit>^..HEAD
```

**IMPORTANT**: Save this diff content — you will need to pass it to subagents. This is the source of truth for all changed code.

## Output File Naming

The review summary file should be named:
```
review-summary-<commit_sha>.md
```

Use the short SHA (first 7 characters) for the filename.

Example: `review-summary-abc1234.md`

## Workflow

1. Run `git log --oneline <commit>^..HEAD` to see the commits being reviewed
2. Run `git diff <commit>^..HEAD --stat` to get a high-level view of files changed
3. Run `git diff <commit>^..HEAD` to get the full diff — **save this for subagents**
4. Segment each file's diff into logical code units (see [code-segmentation.md](code-segmentation.md))
5. Generate `review-summary-<commit_sha>.md` with segments organized by file

## Commit Range Notes

The syntax `<commit>^..HEAD` means:
- `<commit>^`: The parent of the specified commit (exclusive)
- `HEAD`: Current branch tip (inclusive)
- This captures all changes from the commit through the current state
