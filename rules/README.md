# Code Review Rules

This directory contains rules that guide the automated code review process. Each rule defines a specific coding standard, best practice, or pattern that the review system checks for when analyzing pull requests.

## Rule Structure

Rules are markdown files with YAML frontmatter that defines metadata about the rule. The structure is:

```markdown
---
description: Brief description of what the rule checks
category: category-name
applies_to:
  file_extensions: [".ext1", ".ext2"]
---

# Rule Title

[Detailed explanation of the rule, with examples of good and bad code]

## Requirements

[Specific requirements and patterns to look for]

## What to Check

[Guidance for reviewers on what to look for]

## GitHub Comment

```
[Template comment to post when this rule is violated]
```
```

## Metadata Fields

### description
A concise summary of what the rule checks. This appears in rule listings and helps quickly identify the rule's purpose.

Example: `"Prefer guard statements when returning nil early from a method."`

### category
Groups related rules together. Common categories include:
- `clarity` - Code readability and maintainability
- `architecture` - System design and structure patterns
- `apis-apple` - Apple platform API usage
- `apis-custom` - Project-specific API usage
- `performance` - Performance-related patterns
- `safety` - Memory safety and crash prevention

### applies_to
Defines which files the rule should be applied to:
- `file_extensions` - Array of file extensions (e.g., `[".swift", ".m", ".h"]`)

## Rule Content

The markdown body should include:

1. **Overview** - Explain what the rule is about and why it matters
2. **Requirements** - Specific patterns to follow, with code examples
3. **Good vs Bad Examples** - Show concrete code examples with ❌ and ✅ markers
4. **What to Check** - Practical guidance for applying the rule during review
5. **GitHub Comment** - Template text to use when posting review comments

## Directory Organization

Rules can be organized in subdirectories by category or domain:

```
rules/
├── README.md              # This file
├── examples/              # Example rules (not used in actual reviews)
│   ├── example-rule.md
│   └── ...
└── [your-rules]/          # Your actual rules organized by category
    ├── category1/
    │   ├── rule1.md
    │   └── rule2.md
    └── category2/
        └── rule3.md
```

## Creating New Rules

1. Choose the appropriate category or create a new one
2. Create a markdown file with a descriptive name (kebab-case)
3. Add YAML frontmatter with required metadata
4. Write clear requirements with code examples
5. Include a template comment for reviewers to use

## Example Rule

See `examples/example-rule.md` for a complete example of a well-structured rule.

## Using Rules in Reviews

The code review system automatically:
1. Reads all rule files from the `rules/` directory (excluding `examples/`)
2. Applies rules based on file extension matching
3. Uses the rules to guide AI-generated code reviews
4. References specific rules in review comments

Rules are advisory - they guide the review process but reviewers make final decisions about what feedback to provide.
