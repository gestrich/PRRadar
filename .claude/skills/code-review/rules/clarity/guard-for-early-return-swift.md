---
description: Prefer guard statements when returning nil early from a method.
category: clarity
applies_to:
  file_extensions: [".swift"]
---

# Guard for Early Return

When a method returns an optional and you need to return `nil` early, use a `guard` statement instead of `if` with `return`. This makes it immediately clear that execution will not continue past this point.

## Requirements

### Prefer Guard Over If-Return

`guard` should be preferred over `if` with `return`:

```swift
// ❌ Bad: if with return
if id.isEmpty {
    return nil
}

// ✅ Good: guard
guard !id.isEmpty else {
    return nil
}
```

### Exit As Early As Possible

Place guard statements as high in the method as you can. Validate preconditions and exit immediately rather than letting invalid state flow deeper into the method:

```swift
// ❌ Bad: Validation buried in the middle of the method
func processOrder(_ order: Order?) -> Receipt? {
    let timestamp = Date()
    let formatter = ReceiptFormatter()

    if order == nil {
        return nil
    }

    if order!.items.isEmpty {
        return nil
    }

    // ... process order
}

// ✅ Good: Guards at the top, exit immediately on invalid input
func processOrder(_ order: Order?) -> Receipt? {
    guard let order = order else {
        return nil
    }
    guard !order.items.isEmpty else {
        return nil
    }

    let timestamp = Date()
    let formatter = ReceiptFormatter()
    // ... process order
}
```

### Why Guard is Preferred

1. **Explicit early exit** — `guard` signals "stop here if this fails" — the reader knows immediately that execution won't continue
2. **Flattened code** — Keeps the happy path at the top indentation level
3. **Unwrapped values available** — When unwrapping optionals, the unwrapped value is available after the guard

```swift
// ❌ Bad: Nested conditionals, return nil buried at end
func processData(_ data: Data?) -> Result? {
    if let data = data {
        if let decoded = try? decoder.decode(Model.self, from: data) {
            return Result(model: decoded)
        }
    }
    return nil
}

// ✅ Good: Guard statements with clear early exits
func processData(_ data: Data?) -> Result? {
    guard let data = data else {
        return nil
    }
    guard let decoded = try? decoder.decode(Model.self, from: data) else {
        return nil
    }
    return Result(model: decoded)
}
```

## What to Check

When reviewing Swift code that returns optionals:

1. **Early nil returns** — Look for `if condition { return nil }` patterns that should be `guard`
2. **Nested unwrapping** — Multiple `if let` statements that could be flattened with `guard let`
3. **Return nil at method end** — A `return nil` at the end of a method often indicates missing guards earlier

## GitHub Comment

```
Consider using `guard` instead of `if-return` when returning `nil` early. Guard statements make it explicit that execution will not continue past this point, improving code clarity.
```
