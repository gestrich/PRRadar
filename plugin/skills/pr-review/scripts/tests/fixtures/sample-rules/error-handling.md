---
description: Handle exceptions explicitly instead of silently catching all errors
category: safety
model: claude-sonnet-4-20250514
documentation_link: https://docs.example.com/rules/error-handling
applies_to:
  file_patterns:
    - "*.py"
grep:
  any:
    - "except"
    - "Exception"
---

# Error Handling

Exceptions should be handled explicitly with specific exception types and meaningful error handling logic.

## Bad Examples

```python
try:
    do_something()
except:
    pass  # Silent catch-all

try:
    do_something()
except Exception:
    pass  # Catches everything but still does nothing
```

## Good Examples

```python
try:
    do_something()
except ValueError as e:
    logger.error(f"Invalid value: {e}")
    raise

try:
    do_something()
except SpecificError:
    return default_value
```

## GitHub Comment

Avoid bare `except` or `except Exception` clauses that silently swallow errors. Instead:
1. Catch specific exception types
2. Log the error or handle it meaningfully
3. Re-raise if appropriate
