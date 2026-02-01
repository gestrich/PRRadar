---
description: Methods should not accept nil only to return nil — require non-nil or handle nil meaningfully.
category: architecture
applies_to:
  file_extensions: [".swift", ".m", ".mm"]
---

# Weak Client Contracts

A method that accepts an optional parameter but simply returns `nil` when that parameter is `nil` has a weak contract. The caller cannot understand the method's expectations without reading its implementation.

## Requirements

### Don't Accept Nil Just to Return Nil

If a method cannot do meaningful work with a `nil` input, require a non-nil parameter instead:

```swift
// ❌ Bad: Accepts nil but just returns nil — weak contract
func formatName(_ name: String?) -> String? {
    guard let name = name else {
        return nil
    }
    return name.capitalized
}

// ✅ Good: Requires non-nil — contract is clear
func formatName(_ name: String) -> String {
    return name.capitalized
}
```

```objc
// ❌ Bad: Accepts nullable but just returns nil — weak contract
- (nullable NSString *)formatName:(nullable NSString *)name {
    if (name == nil) {
        return nil;
    }
    return name.capitalizedString;
}

// ✅ Good: Requires nonnull — contract is clear
- (NSString *)formatName:(NSString *)name {
    return name.capitalizedString;
}
```

### Why This Matters

1. **Unclear expectations** — The caller cannot know if `nil` is a valid input or a programming error without reading the implementation
2. **Error propagation** — `nil` silently flows through the system instead of failing at the source
3. **Debugging difficulty** — When something fails downstream, it's hard to trace back to where `nil` was first introduced
4. **API trust** — Callers may pass `nil` thinking it's handled, when really the method just gives up

### Valid Reasons to Accept Nil

Accepting `nil` is appropriate when the method has meaningful behavior for `nil` input:

```swift
// ✅ OK: Nil has meaningful behavior (returns default)
func displayName(_ name: String?) -> String {
    return name ?? "Unknown"
}

// ✅ OK: Nil is a valid "not set" state
func updateUserName(_ name: String?) {
    if let name = name {
        user.name = name
    }
    // nil means "don't change" — that's meaningful
}
```

```objc
// ✅ OK: Nil has meaningful behavior (returns default)
- (NSString *)displayName:(nullable NSString *)name {
    return name ?: @"Unknown";
}
```

### Push Validation to the Caller

When you require non-nil, the caller is forced to handle the optional explicitly:

```swift
// Caller must decide what to do with nil
if let name = optionalName {
    let formatted = formatName(name)  // Clear: formatName requires a value
    // ...
}
```

This makes the code's assumptions visible at the call site rather than hidden in the implementation.

## What to Check

When reviewing methods with optional parameters:

1. **Nil-in, nil-out** — Method accepts optional and returns nil when input is nil
2. **Guard-and-return-nil** — First line is `guard let x = x else { return nil }`
3. **Nullable with no nil handling** — Objective-C nullable parameter that's only checked to bail out

## GitHub Comment

```
This method accepts nil but just returns nil when it receives nil. Consider requiring a non-nil parameter instead — this makes the contract clear and pushes validation to the caller.
```
