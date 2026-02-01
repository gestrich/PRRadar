# Interpreting @code-review Requests

When a user mentions `@code-review` in a PR comment, analyze their request and return a structured JSON action indicating what should be done.

## Output Format

Return a JSON object with an `action` field and action-specific details. The workflow will handle executing the action.

## Action Types

### 1. `performReview` - Trigger a Full Code Review

Use when the user wants a code review performed.

**Indicators:**
- Just `@code-review` with no special request
- "please review", "review this", "check this PR"
- "re-review", "review again", "check again"
- Requests for specific rule or file focus (these trigger a review with filters)

**Output:**
```json
{
  "action": "performReview",
  "additionalInstructions": "Focus on nullability issues",
  "filterFiles": ["*.h", "*.m"],
  "filterRules": ["nullability-h-objc"]
}
```

Fields:
- `additionalInstructions`: Optional string with extra context for the review
- `filterFiles`: Optional array of glob patterns to limit which files are reviewed
- `filterRules`: Optional array of rule names to limit which rules are checked

**Examples:**
| User Comment | Output |
|--------------|--------|
| `@code-review` | `{"action": "performReview"}` |
| `@code-review please review` | `{"action": "performReview"}` |
| `@code-review check nullability` | `{"action": "performReview", "filterRules": ["nullability-h-objc", "nullability-m-objc"]}` |
| `@code-review review MyFile.swift only` | `{"action": "performReview", "filterFiles": ["**/MyFile.swift"]}` |
| `@code-review I fixed the issues, please check again` | `{"action": "performReview", "additionalInstructions": "User says they fixed previous issues - compare with prior review if available"}` |

---

### 2. `postComment` - Post a New Comment

Use when the user asks a question or makes a request that can be answered directly without running a review.

**Indicators:**
- "explain", "what does", "what is", "how does"
- "why is this flagged", "what rule"
- Questions about rules, categories, or the review process
- Asking about available rules or capabilities

**Output:**
```json
{
  "action": "postComment",
  "body": "The nullability rule checks for explicit nullability annotations on Objective-C object pointers..."
}
```

**Examples:**
| User Comment | Output |
|--------------|--------|
| `@code-review explain the nullability rule` | `{"action": "postComment", "body": "## Nullability Rule\n\nThe nullability rules check..."}` |
| `@code-review what rules are available?` | `{"action": "postComment", "body": "## Available Rules\n\n- **architecture**: ..."}` |
| `@code-review why is NS_ASSUME_NONNULL not allowed?` | `{"action": "postComment", "body": "## NS_ASSUME_NONNULL\n\nThe coding standard requires..."}` |

---

### 3. `replyToComment` - Reply to an Existing Comment

Use when the user is responding to a specific review comment and wants a reply in that thread.

**Indicators:**
- Comment is on a review thread (not the main PR conversation)
- User references "this comment", "this violation", "this issue"
- Asking for clarification about a specific inline review comment

**Output:**
```json
{
  "action": "replyToComment",
  "commentId": 123456789,
  "body": "Good question! This is flagged because..."
}
```

Note: The `commentId` is provided by the workflow context.

---

### 4. `replaceComment` - Edit an Existing Comment

Use when a previous @code-review comment should be updated rather than adding a new one.

**Indicators:**
- User asks to "update", "edit", or "revise" a previous response
- Correcting an error in a previous comment

**Output:**
```json
{
  "action": "replaceComment",
  "commentId": 123456789,
  "body": "Updated response based on new information..."
}
```

Note: The `commentId` should reference a previous @code-review comment.

---

### 5. `postSummary` - Post a Summary Comment

Use when responding with a summary or overview that doesn't fit other categories.

**Indicators:**
- Asking for a summary of previous reviews
- Requesting comparison between reviews
- "what was found", "show results", "summarize"

**Output:**
```json
{
  "action": "postSummary",
  "body": "## Review Summary\n\nBased on the previous reviews..."
}
```

---

## Decision Flow

```
User mentions @code-review
         │
         ▼
  Is this a question about rules/process?
         │
    ┌────┴────┐
   Yes        No
    │          │
    ▼          ▼
postComment   Does user want a review?
              │
         ┌────┴────┐
        Yes        No
         │          │
         ▼          ▼
 performReview    Is this a reply to a thread?
                  │
             ┌────┴────┐
            Yes        No
             │          │
             ▼          ▼
    replyToComment    postSummary
```

## Rule Name Mapping

When users mention rules by common names, map to the actual rule identifiers:

| User Mentions | Rule Identifiers |
|---------------|------------------|
| nullability | `nullability-h-objc`, `nullability-m-objc` |
| architecture | Rules in `architecture/` folder |
| clarity | Rules in `clarity/` folder |
| service locator | `service-locator` |
| import order | `import-order-h`, `import-order-m`, `import-order-swift` |
| generics | `generics-objc` |
| localization | `localization-swift`, `localization-objc` |
| property access | `property-access-objc` |
| weak contracts | `weak-client-contracts` |

## Context Available

When interpreting requests, you have access to:
- The full comment body from the user
- PR number and URL
- Whether the comment is on a review thread or the main PR conversation
- Comment ID if replying to an existing comment

## Error Handling

If the request is ambiguous or cannot be understood, use `postComment` with a helpful response:

```json
{
  "action": "postComment",
  "body": "I'm not sure what you'd like me to do. Here are some options:\n\n- `@code-review` - Run a full code review\n- `@code-review nullability` - Review for nullability issues only\n- `@code-review explain {rule}` - Explain a specific rule\n\nWhat would you like me to do?"
}
```
