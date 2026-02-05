---
description: Use proper async/await patterns
category: best-practices
applies_to:
  file_patterns:
    - "*.py"
grep:
  any:
    - "async"
    - "await"
---

# Async Patterns

When using async/await, follow best practices for proper concurrency handling.

## Guidelines

- Always await async functions
- Use asyncio.gather for concurrent operations
- Handle exceptions in async code properly

## GitHub Comment

Review your async code for proper await usage and exception handling.
