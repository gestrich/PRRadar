---
name: code-review
description: Analyzes git diffs and generates structured markdown summaries of code changes. Use when reviewing commits, understanding what changed in a branch, creating change documentation, or reviewing pull requests.
user-invocable: true
model-invocable: false
---

# Code Review

Analyzes code changes from a specified commit or pull request, segments each file into logical code units (methods, declarations, etc.), reviews each segment against applicable rules, and generates a structured summary.

```
┌─────────────┐
│ Input       │  (commit SHA, PR link, or PR #)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Get Diff    │  (gh pr diff / git diff)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ List Files  │  (extract changed files)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Segment     │  (parse each file's diff into logical units)
│ Files       │
└──────┬──────┘
       │
       ▼
┌───────────────────┐
│ review-summary-   │  (segments × rules as checkboxes)
│    <id>.md        │
└─────────┬─────────┘
       │
       ▼
┌─────────────────────────────────────┐
│  For each Segment × Rule:           │
│  ┌───────┐ ┌───────┐ ┌───────┐      │
│  │Agent 1│ │Agent 2│ │Agent 3│ ...  │  (parallel)
│  └───┬───┘ └───┬───┘ └───┬───┘      │
│      │         │         │          │
│      └─────────┼─────────┘          │
│                ▼                    │
│      Update review-summary-<id>.md  │
│             [x] Score: 3            │
└─────────────────────────────────────┘
       │
       ▼
┌─────────────┐
│  Summary    │  (violations by rule + by segment)
└─────────────┘
```

## Usage

```
/code-review <commit-sha>
/code-review <pr-link>
/code-review <pr-number>
```

The skill accepts:
- **Commit SHA**: Analyzes changes from the specified commit through HEAD
- **PR link**: Analyzes changes in the pull request (e.g., `https://github.com/owner/repo/pull/123`)
- **PR number**: Analyzes changes in the PR by number (e.g., `#123` or `123`)

## Process

1. **Detect input type**: Determine if input is a commit SHA, PR link, or PR number
2. **Get the diff**: Retrieve the relevant changes
3. **List changed files**: Extract all files from the diff
4. **Segment each file**: Parse each file's diff into logical code segments (methods, declarations, etc.)
5. **Create review summary**: Generate `review-summary-<id>.md` (where `<id>` is the PR number or commit SHA) with segments organized by file, each segment having checkboxes for applicable rules
6. **Execute reviews**: Spawn one subagent per segment × rule combination, updating the plan with scores and details
7. **Generate summary**: Violation counts by rule, then detailed results by segment

## Code Segmentation

Each file's diff is parsed into logical **segments**. See [code-segmentation.md](code-segmentation.md) for detailed instructions on segment types, change status definitions, and segmentation rules.

## Review Summary Format

The `review-summary-<id>.md` file uses checkboxes that subagents check off as they complete their review. Each file contains segments, and each segment has checkboxes for applicable rules.

**See [template.md](template.md) for the complete output format template.**

The `<id>` in the filename is:
- For PRs: the PR number (e.g., `review-summary-18500.md`)
- For commits: the short commit SHA (e.g., `review-summary-abc1234.md`)

```markdown
# Review Summary: <PR title or commit range>

## Overview
Brief description of what this change does overall.

**Files Changed:** 3
**Total Segments:** 8
**Applicable Rules:** 2

---

## File: `path/to/MyService.swift`

### Segment: Method `fetchUserData()` (modified)

```swift
func fetchUserData() async {
+   let result = await networkClient.fetch(userID)
+   self.userData = result
}
```

#### Rule Reviews
- [ ] **error-handling** | Score: ? | Details: ?
- [ ] **thread-safety** | Score: ? | Details: ?

---

### Segment: Method `handleResponse(_:)` (added)

```swift
+func handleResponse(_ response: Response) {
+    guard let data = response.data else { return }
+    process(data)
+}
```

#### Rule Reviews
- [ ] **error-handling** | Score: ? | Details: ?
- [ ] **thread-safety** | Score: ? | Details: ?

---

## File: `path/to/FFLayerManager.h`

### Segment: Interface declaration (modified)

```objective-c
 @interface FFLayerManager : NSObject
+@property (nonatomic, strong) NSArray *layers;
 @end
```

#### Rule Reviews
- [ ] **nullability/nullability_h_files** | Score: ? | Details: ?

---

## File: `path/to/config.json`

### Segment: Root object (modified)

```json
 {
+  "newKey": "value"
 }
```

#### Rule Reviews
*No applicable rules for this file type.*

---
```

### After Subagent Review

When a subagent completes its review, it updates the checkbox, score, and details. For violations (score >= 5), include the diff line number and code snippets showing the specific problematic code:

```markdown
#### Rule Reviews
- [x] **error-handling** | Score: 8 | Line: 42 | Details: Missing error handling for network timeout
  ```swift
  let result = await networkClient.fetch(userID)  // ← No error handling
  ```
- [x] **thread-safety** | Score: 1 | Details: No threading concerns - all code runs on main actor
```

## Scoring

The score measures **how clearly the code violates the rule**, not the risk or severity of the violation.

- **Score 1-2**: No violation - code follows this rule well
- **Score 3-4**: Unlikely violation - minor ambiguity but probably fine
- **Score 5-6**: Unclear - could be interpreted as a violation depending on context
- **Score 7-8**: Likely violation - code appears to break the rule
- **Score 9-10**: Clear violation - code definitively breaks the rule

## Review Rules

Rules are defined in the `rules/` folder (in the same directory as this skill). Rules can be:
- A `.md` file directly in `rules/` (e.g., `rules/core-data.md`)
- A `.md` file in a subfolder (e.g., `rules/nullability/nullability_h_files.md`)

The rule name is the path relative to `rules/` without the `.md` extension (e.g., `nullability/nullability_h_files`).

### Rule Frontmatter

Rules can have YAML frontmatter to describe the rule and specify when it applies:

```yaml
---
description: Brief description of what this rule checks for.
documentation: https://github.com/org/repo/path/to/docs/RuleName.md
applies_to:
  file_extensions: [".h"]
---
```

- **`description`**: Brief summary of the rule's purpose
- **`documentation`**: Link to detailed documentation for this rule. **This link MUST be included in the summary** — in both the "Violations by Rule" table and the "Violation Details" section headers for any rule with violations.
- **`applies_to.file_extensions`**: Only run this rule if the diff contains files matching these extensions. If omitted, the rule applies to all files.

### Skipped Rules

If a rule file starts with `> **SKIPPED:**`, skip that rule entirely during review. Only process rules that do not have this marker.

## Review Execution

After generating the review plan:

**IMPORTANT**: For PR reviews, the changed files may not exist locally — they only exist in the PR diff. You MUST pass the actual segment diff content to subagents. Do NOT instruct subagents to read files from the filesystem.

**CRITICAL: Subagent Requirement** — You MUST use subagents for each rule evaluation, regardless of diff size. Even if the diff appears small or simple, do NOT skip subagents or reason that you can review it inline. Each rule requires dedicated, focused attention that only a subagent can provide. The quality of review depends on isolated, focused rule evaluation.

1. **For each Segment** in `review-summary-<id>.md`:
   - **For each Rule** checkbox under that segment:
     - Spawn a subagent using the Task tool with `subagent_type: "general-purpose"` and `model: "sonnet"` (latest sonnet model)
     - The subagent prompt **MUST include**:
       - The rule name
       - **Instruction to read the rule file** at `plugin/skills/pr-review/rules/{rule_name}.md` (use full path from repo root)
       - The file path and segment identifier (e.g., "Method `fetchUserData()`")
       - The segment type (method, interface, properties, etc.)
       - **The actual segment diff content** (copy/paste the segment's diff into the prompt)
       - Instructions to score 1-10 and provide details
     - The subagent updates `review-summary-<id>.md`:
       - Checks the box: `- [ ]` → `- [x]`
       - Fills in the score: `Score: ?` → `Score: 3`
       - Fills in details: `Details: ?` → `Details: <explanation>`

2. **Run segment reviews in parallel** where possible (multiple subagents can review different segments/rules concurrently)

3. **After all reviews complete**, add a summary section at the end of `review-summary-<id>.md`. **Important**: The documentation links in the summary come from each rule's frontmatter `documentation` field:

```markdown
---

## Summary

### Violations by Rule

| Rule | Violations | Documentation |
|------|------------|---------------|
| nullability/nullability_h_files | 3 | [Nullability Guide](https://github.com/org/repo/path/to/Nullability.md) |
| error-handling | 2 | [Error Handling Guide](https://github.com/org/repo/path/to/ErrorHandling.md) |

### Results by File

| File | Segments | Highest Score | Primary Concern |
|------|----------|---------------|-----------------|
| MyService.swift | 2 | 8 | error-handling |
| FFLayerManager.h | 2 | 9 | nullability/nullability_h_files |
| config.json | 1 | - | No applicable rules |

### Violation Details

#### error-handling (2 segments) — [Documentation](https://github.com/org/repo/path/to/ErrorHandling.md)

**MyService.swift → Method `fetchUserData()`** (Score: 8, Line: 42)
Missing error handling for network request.
```swift
let result = await networkClient.fetch(userID)  // ← No error handling
```

**MyService.swift → Method `handleResponse(_:)`** (Score: 6, Line: 58)
Guard statement silently returns on nil data without logging.

#### nullability/nullability_h_files (3 segments) — [Documentation](https://github.com/org/repo/path/to/Nullability.md)

**FFLayerManager.h → Interface declaration** (Score: 9, Line: 15)
Uses NS_ASSUME_NONNULL_BEGIN/END which is prohibited.
```objective-c
NS_ASSUME_NONNULL_BEGIN  // ← Prohibited
@interface FFLayerManager : NSObject
```

**FFLayerManager.h → Properties** (Score: 7, Line: 23)
Property `layers` missing explicit nullability annotation.

### Recommended Actions

1. Add error handling for network request in `fetchUserData()`
2. Add logging in `handleResponse(_:)` guard clause
3. Remove `NS_ASSUME_NONNULL_BEGIN/END` and add explicit annotations
```

## Subagent Prompt Template

When spawning a segment-review subagent, use this prompt structure.

**CRITICAL**: You MUST include the actual segment diff content in the prompt. The subagent cannot access PR files directly — they only exist in the diff. Copy the segment's diff into the prompt.

```
You are reviewing a code segment for the "{rule_name}" rule.

Your task:
1. First, read the rule documentation at: plugin/skills/pr-review/rules/{rule_name}.md
2. Review the segment diff content provided below (DO NOT try to read files from filesystem - they may not exist locally)
3. Evaluate whether this segment violates the rule
4. Score from 1-10 based on how clearly the code violates the rule:
   - 1-2: No violation - code follows this rule well
   - 3-4: Unlikely violation - minor ambiguity but probably fine
   - 5-6: Unclear - could be interpreted as a violation depending on context
   - 7-8: Likely violation - code appears to break the rule
   - 9-10: Clear violation - code definitively breaks the rule
5. Provide brief, specific details explaining the score
6. For any violation (score >= 5), note the **target file line number** (from the diff hunk header, NOT a cumulative count) and include a code snippet showing the problematic code

File: {file_path}
Segment: {segment_name} ({segment_type})
Change Status: {added|modified|removed}

## Segment Diff Content

The following is the actual diff content for this segment. Analyze this directly:

```diff
{PASTE THE SEGMENT'S DIFF HERE - this is required!}
```

After your analysis, update `review-summary-<id>.md`:
1. Find the section for file "{file_path}", segment "{segment_name}", rule "{rule_name}"
2. Change `- [ ]` to `- [x]`
3. Change `Score: ?` to `Score: {your_score}`
4. For violations (score >= 5), add `| Line: {target_file_line_number}` after the score (e.g., `Score: 8 | Line: 42`)
5. Change `Details: ?` to `Details: {your_explanation}`

Keep details concise (1-2 sentences). The line number must be the **target file line number** calculated from the diff hunk header (e.g., `@@ -0,0 +1,10 @@` means lines 1-10), NOT a cumulative count of lines in the diff output. See "Calculating Line Numbers from Diffs" section for details.
```

## Instructions

### Detecting Input Type

Determine what type of input was provided:
- **PR link/number**: Follow instructions in [reviewing-pr-diff.md](reviewing-pr-diff.md)
- **Commit SHA**: Follow instructions in [reviewing-local-diff.md](reviewing-local-diff.md)

### Segmenting the Diff

After retrieving the diff, segment it into logical units. See [code-segmentation.md](code-segmentation.md) for detailed instructions.

### Executing the Review

After retrieving the diff and segmenting it:

1. Read all files in `rules/` folder to get the list of rules (skip any that start with `> **SKIPPED:**`)
2. Generate `review-summary-<id>.md` with segments organized by file, each segment having checkboxes for applicable rules
3. Execute the review by spawning subagents for each segment/rule combination, **passing the segment's diff in each subagent prompt**
4. After all subagents complete, add the summary section with violations by rule and results by segment

## Structured Output Format (GitHub Actions)

When running in GitHub Actions with a JSON schema, the structured output must include:

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
      }
    }
  }
}
```

**Important:**
- Only include items in `feedback` array that have `score >= 5` (violations)
- The `githubComment` should be a concise, actionable comment suitable for posting on GitHub
- The `lineNumber` must be the **target file line number** (see [Calculating Line Numbers](#calculating-line-numbers-from-diffs) below)
- Categories in `summary.categories` should match the rule category names (folder names in `rules/`)
- The `aggregateScore` is the highest score found in that category

## Calculating Line Numbers from Diffs

The `lineNumber` field must contain the **target file line number** where the violation occurs — NOT a cumulative count of lines in the diff output. GitHub's PR comment API only accepts line numbers that exist in the target file.

### Using the parse-diff Tool

The `parse-diff` command deterministically parses diff hunk headers and provides structured JSON output with correct `new_start` line numbers for each file section.

```bash
# Parse PR diff and get structured JSON with line numbers
gh pr diff 7 | plugin/skills/pr-review/scripts/parse-diff

# Parse from a saved diff file
plugin/skills/pr-review/scripts/parse-diff --input-file diff.txt

# Debug output in text format
gh pr diff 7 | plugin/skills/pr-review/scripts/parse-diff --format text
```

### Using --annotate-lines (Recommended for Subagents)

**IMPORTANT**: When passing diff content to subagents, use `--annotate-lines` to prepend explicit line numbers to each diff line. This removes ambiguity and prevents line number calculation errors.

```bash
# Parse with line numbers annotated in the content
gh pr diff 7 | plugin/skills/pr-review/scripts/parse-diff --annotate-lines
```

**Output with `--annotate-lines`:**
```json
{
  "hunks": [
    {
      "file_path": "test-files/FFLogger.h",
      "new_start": 1,
      "new_length": 10,
      "old_start": 0,
      "old_length": 0,
      "content": "...\n@@ -0,0 +1,10 @@\n   1: +#import <Foundation/Foundation.h>\n   2: +\n   3: +@interface FFLogger : NSObject\n   4: +\n   5: +@property (nonatomic, strong) NSString *logLevel;\n..."
    }
  ]
}
```

**Annotation format:**
- Added lines (`+`) and context lines (` `) show their target file line number: `  5: +code`
- Deleted lines (`-`) show no line number: `   -: -deleted code`
- Header lines are preserved as-is

This makes it explicit that `@property ... logLevel` is at **line 5** in the target file, removing ambiguity for subagents.

**Output without `--annotate-lines`:**
```json
{
  "hunks": [
    {
      "file_path": "test-files/FFLogger.h",
      "new_start": 1,
      "new_length": 10,
      "old_start": 0,
      "old_length": 0,
      "content": "+#import <Foundation/Foundation.h>\n..."
    }
  ]
}
```

Without annotation, subagents must manually calculate line numbers using `new_start` as the anchor point, which is error-prone.

### Reading the Hunk Header

Each diff section starts with a hunk header in this format:

```
@@ -old_start,old_count +new_start,new_count @@ optional context
```

- `-old_start,old_count`: Lines from the original file (before changes)
- `+new_start,new_count`: Lines in the target file (after changes)

**The `lineNumber` you report must be a line number in the target file (the `+new_start` side).**

### Example 1: New File

For a new file like `test-files/FFLogger.h`:

```diff
diff --git a/test-files/FFLogger.h b/test-files/FFLogger.h
new file mode 100644
index 0000000..f961bc5
--- /dev/null
+++ b/test-files/FFLogger.h
@@ -0,0 +1,10 @@
+#import <Foundation/Foundation.h>
+
+@interface FFLogger : NSObject
+
+@property (nonatomic, strong) NSString *logLevel;
+
+- (instancetype)initWithLevel:(NSString *)level;
+- (void)log:(NSString *)message;
+
+@end
```

The hunk header `@@ -0,0 +1,10 @@` means:
- `-0,0`: No lines from old file (it didn't exist)
- `+1,10`: New file starts at line 1, has 10 lines

**Counting target file lines:**
| Diff Line | Content | Target File Line |
|-----------|---------|------------------|
| `+#import <Foundation/Foundation.h>` | import | **1** |
| `+` | blank | **2** |
| `+@interface FFLogger : NSObject` | interface | **3** |
| `+` | blank | **4** |
| `+@property ... *logLevel;` | property | **5** |
| `+` | blank | **6** |
| `+- (instancetype)initWithLevel:...` | method | **7** |
| `+- (void)log:...` | method | **8** |
| `+` | blank | **9** |
| `+@end` | end | **10** |

If the `logLevel` property violates a rule, report `lineNumber: 5` (not the position in the overall diff output).

### Example 2: Modified File

For a modified file with hunk header `@@ -118,98 +118,36 @@ jobs:`:
- `-118,98`: Old file section starts at line 118, spans 98 lines
- `+118,36`: Target file section starts at line 118, spans 36 lines

**Line counting rules:**
- **Context lines** (space prefix ` `): Count them — they exist in target file
- **Added lines** (`+` prefix): Count them — they're new in target file
- **Removed lines** (`-` prefix): **Skip them** — they don't exist in target file

```diff
@@ -118,98 +118,36 @@ jobs:
           claude_args: --allowedTools...      ← Line 119 (context)
                                               ← Line 120 (blank context)
-      - name: Parse structured output         ← SKIP (removed line)
-        id: parse-output                      ← SKIP (removed line)
       - name: Save execution file             ← Line 121 (context)
+      - name: Setup Python                    ← Line 126 (added line)
```

### Common Mistake

**WRONG:** Counting cumulative lines through the entire diff output
- If a diff has 2416 total lines and the violation appears near the end, do NOT report `lineNumber: 2411`

**RIGHT:** Reading the hunk header and counting target file lines
- Read `@@ -0,0 +1,10 @@`, count added/context lines from line 1, report `lineNumber: 5`

## Examples

```
/code-review abc1234
```
Reviews all changes from commit `abc1234` through the current HEAD.

```
/code-review https://github.com/owner/repo/pull/18500
```
Reviews all changes in PR #18500.

```
/code-review #18500
```
Reviews all changes in PR #18500 (shorthand).

```
/code-review 18500
```
Reviews all changes in PR #18500 (number only).
