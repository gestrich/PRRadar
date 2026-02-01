# Handling GitHub @code-review Requests

When a user mentions `@code-review` in a PR comment, you receive their request text along with the PR URL. This guide explains how to interpret and respond to different types of requests.

## Request Types

### 1. Basic Code Review (No Special Request)

If the user's comment is just `@code-review` or doesn't specify any particular focus:

**Action**: Run a full code review using the standard process in [skill.md](skill.md).

**Example comments**:
- `@code-review`
- `@code-review please review this PR`
- `@CodeReview`

**Response**: Follow the full code review process, then post a summary comment with violations found.

---

### 2. Review for Specific Rule or Category

If the user asks for a review focused on a specific rule, rule folder, or category:

**Action**:
1. Identify which rules match their request
2. Run the review using only those rules
3. Provide detailed feedback for that specific area

**Example comments**:
- `@code-review check nullability` → Run only rules in `rules/apis-apple/nullability-objc/`
- `@code-review architecture only` → Run only rules in `rules/architecture/`
- `@code-review check service locator usage` → Run only `rules/apis-ffm/service-locator.md`
- `@code-review focus on import order` → Run import order rules

**Rule folder mapping**:
| User mentions | Rule folder/files |
|---------------|-------------------|
| nullability | `rules/apis-apple/nullability-objc/` |
| architecture | `rules/architecture/` |
| clarity | `rules/clarity/` |
| service locator | `rules/apis-ffm/service-locator.md` |
| import order | `rules/apis-apple/import-order-*.md` |
| generics | `rules/apis-apple/generics-objc.md` |
| localization | `rules/apis-apple/localization-*.md` |
| property access | `rules/apis-apple/property-access-objc.md` |
| weak contracts | `rules/architecture/weak-client-contracts.md` |

**Response**: Post a comment summarizing findings for the requested rules only.

---

### 3. Review Specific File

If the user asks for a review of a specific file in the PR:

**Action**:
1. Get the PR diff
2. Extract only the segments for the specified file
3. Run all applicable rules against those segments

**Example comments**:
- `@code-review check MyService.swift`
- `@code-review review FFLayerManager.h only`
- `@code-review focus on the changes in NetworkClient.m`

**Response**: Post a comment with findings for that specific file.

---

### 4. Explain a Rule

If the user asks for more explanation about a rule or why something is flagged:

**Action**:
1. Read the rule file at `.claude/skills/code-review/rules/{rule_name}.md`
2. Check if the rule has a `documentation` field in its frontmatter
3. If documentation exists, fetch that URL to get more detailed context
4. Explain the rule in the context of their specific code changes

**Example comments**:
- `@code-review explain the nullability rule`
- `@code-review why is NS_ASSUME_NONNULL not allowed?`
- `@code-review what does the weak-client-contracts rule mean?`
- `@code-review can you explain why this is flagged?`

**Response**:
1. Quote the relevant code from the PR
2. Explain what the rule checks for
3. Reference the documentation link from the rule's frontmatter
4. Provide specific guidance on how to fix the issue in their code

**Documentation lookup**:
```yaml
# From rule frontmatter:
documentation: https://github.com/org/repo/path/to/docs.md
```

Use `gh api` or WebFetch to retrieve the documentation content and provide a thorough explanation.

---

### 5. Re-review After Changes

If the user indicates they've made changes and want a re-review:

**Action**: Run the full review process again, comparing to any previous review if mentioned.

**Example comments**:
- `@code-review I fixed the issues, please re-review`
- `@code-review check again`
- `@code-review updated, how does it look now?`

**Response**: Run the review and note any remaining issues or confirm that previous issues are resolved.

---

### 6. Query Prior Run Results

If the user asks about a previous code review run:

**Action**:
1. Find the most recent workflow run for this PR that has a `code-review-pr-{pr_number}` artifact
2. Download the artifact to access the prior review summary
3. Reference the data to answer the user's question

**Example comments**:
- `@code-review what was the last review?`
- `@code-review show prior results`
- `@code-review what violations were found before?`
- `@code-review compare to previous run`

**How to download prior artifacts**:

```bash
# Get the workflow run ID for the most recent code-review run on this PR
RUN_ID=$(gh run list --workflow="Claude Code Review (@mention)" --json databaseId,status --jq '.[0].databaseId')

# Download the artifact
gh run download $RUN_ID --name "code-review-pr-{pr_number}" --dir prior-review/

# Read the prior review summary
cat prior-review/review-summary.md
```

**Response**: Summarize findings from the prior review, or compare with current state if requested.

---

## Response Format

Always respond by posting a comment on the PR using:

```bash
gh pr comment <PR_NUMBER> --body "<your response>"
```

### For Full Reviews

Post the complete violation summary following the format in [skill.md](skill.md).

### For Focused Reviews

Post a shorter summary focusing on the requested area:

```markdown
## Code Review: {Focus Area}

Reviewed the PR for **{rule/category}** violations.

### Findings

{List of violations or "No violations found"}

### Recommendations

{Specific guidance based on findings}
```

### For Rule Explanations

```markdown
## Rule Explanation: {Rule Name}

### What This Rule Checks

{Summary from the rule file}

### Why It Matters

{Explanation with context from documentation}

### In Your Code

{Quote the specific code and explain the issue}

### How to Fix

{Specific fix recommendations}

### Learn More

{Link to documentation from rule frontmatter}
```

## Detecting Request Type

Parse the user's comment to determine intent:

1. **Keywords for specific rules**: Look for rule names, category names, or technical terms (nullability, architecture, imports, etc.)
2. **Keywords for file focus**: Look for file extensions (.swift, .m, .h) or specific filenames
3. **Keywords for explanation**: Look for "explain", "why", "what does", "tell me about"
4. **Keywords for re-review**: Look for "again", "re-review", "fixed", "updated", "check again"
5. **Keywords for prior run**: Look for "last review", "prior", "previous", "before", "what was found", "compare"
6. **No special keywords**: Default to full review

## Error Handling

If you cannot determine what the user wants:

```markdown
I received your @code-review request but I'm not sure what you'd like me to do. Here are some options:

- `@code-review` - Run a full code review
- `@code-review nullability` - Review for nullability issues only
- `@code-review MyFile.swift` - Review a specific file
- `@code-review explain {rule}` - Explain a specific rule
- `@code-review what was the last review?` - Show results from a prior run

What would you like me to do?
```
