---
description: Handle errors explicitly rather than silently ignoring them
category: safety
model: claude-sonnet-4-20250514
applies_to:
  file_extensions: [".py", ".js", ".ts", ".go", ".swift"]
grep:
  any:
    - "try"
    - "catch"
    - "except"
    - "throw"
    - "raise"
    - "\\.catch\\("
---

# Explicit Error Handling

Errors should be handled explicitly at appropriate boundaries rather than silently ignored. Silent failures make debugging difficult and can lead to unexpected behavior or data corruption.

## Requirements

### Don't Ignore Errors

All error conditions should be acknowledged and handled appropriately:

```python
# ❌ Bad: Error silently ignored
try:
    result = risky_operation()
except:
    pass

# ✅ Good: Error logged and handled
try:
    result = risky_operation()
except OperationError as e:
    logger.error(f"Operation failed: {e}")
    return default_value
```

```javascript
// ❌ Bad: Promise rejection ignored
fetchData().then(data => process(data));

// ✅ Good: Rejection handled
fetchData()
    .then(data => process(data))
    .catch(error => {
        console.error("Failed to fetch data:", error);
        handleFetchError(error);
    });
```

### Handle Specific Errors

Catch specific exceptions rather than broad catch-all handlers when possible:

```python
# ❌ Bad: Catches everything, including programming errors
try:
    data = json.loads(response)
    result = process_data(data)
except Exception:
    return None

# ✅ Good: Specific error types with appropriate handling
try:
    data = json.loads(response)
    result = process_data(data)
except json.JSONDecodeError as e:
    logger.warning(f"Invalid JSON response: {e}")
    return None
except ValueError as e:
    logger.error(f"Invalid data format: {e}")
    raise
```

### Document Error Handling Decisions

When deliberately ignoring an error, document why:

```python
# ✅ Good: Documented decision to ignore specific error
try:
    cache.invalidate(key)
except CacheConnectionError:
    # Cache is optional; continue if unavailable
    pass
```

### Why This Matters

1. **Debuggability** — Explicit handling leaves traces for troubleshooting
2. **Reliability** — Prevents silent data corruption or inconsistent state
3. **User experience** — Allows graceful degradation with meaningful error messages
4. **Monitoring** — Logged errors enable alerting and metrics

### Valid Patterns for Error Handling

Different situations call for different approaches:

```python
# ✅ Log and continue
try:
    send_analytics_event(event)
except AnalyticsError as e:
    logger.warning(f"Analytics failed: {e}")
    # Continue - analytics shouldn't block user action

# ✅ Return default value
try:
    return expensive_computation()
except ComputationError:
    return cached_fallback_value

# ✅ Re-raise with context
try:
    data = external_api.fetch(id)
except APIError as e:
    raise DataFetchError(f"Failed to fetch {id}") from e

# ✅ Convert to domain error
try:
    record = database.query(id)
except DatabaseError as e:
    raise RecordNotFoundError(f"No record with id {id}")
```

## What to Check

When reviewing error handling:

1. **Bare except/catch** — Look for `except:` or `catch (e) {}` with no handling
2. **Silent failures** — `pass`, empty catch blocks, or ignored promise rejections
3. **Overly broad catches** — `except Exception` that might hide bugs
4. **Missing logging** — Errors handled but not logged for debugging

## GitHub Comment

```
This error is being silently ignored. Consider logging it or handling it explicitly so failures are visible during debugging and monitoring.
```
