---
name: pr-radar-todo
description: Add an item to the project TODO list with t-shirt size categorization (Small, Medium, Large)
---

Add an item to the project TODO list at `docs/proposed/TODO.md`.

## Workflow

1. Read the user's input (`$ARGUMENTS`) to determine the TODO item title and any details
2. Ask the user which t-shirt size (Small, Medium, Large) applies if not already specified
3. Read the current `docs/proposed/TODO.md` file
4. Append the new item under the correct size section (`## Small`, `## Medium`, or `## Large`)
5. Each item uses checkbox format: `- [ ] Item title`
6. If the user provided a detailed description, add it as indented text beneath the item (indented with 2 spaces)
7. Write the updated file

## Item Format

```markdown
- [ ] Short item title
  Longer description with more context about the idea, rationale,
  or implementation notes. Can be a full paragraph.
```

## File Structure

The TODO file has three sections in this order:

```markdown
# TODO

## Small

- [ ] ...

## Medium

- [ ] ...

## Large

- [ ] ...
```

## Rules

- Always read the existing file before writing to preserve existing items
- If the file does not exist, create it with the three empty sections before adding the item
- Place new items in their respective section, ordered from smallest to largest effort within each category
- Do not modify existing items
- Do not remove the checkbox prefix `- [ ]`
