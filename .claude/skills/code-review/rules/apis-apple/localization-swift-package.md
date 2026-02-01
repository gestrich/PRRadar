---
description: Ensures newly added user-facing strings in Swift packages are properly localized using String Catalogs.
documentation: https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/Localization/LocalizingSwiftPackages.md
category: api-usage
applies_to:
  file_extensions: [".swift"]
  exclude_patterns: ["ffm/**"]
---

# Localization (Swift Packages)

All newly added user-facing strings in Swift packages must be localized using `String(localized:)` with String Catalogs (`.xcstrings`).

## Requirements

### Use String(localized:) with bundle: .module

```swift
// ❌ Bad: Bare string literal
let title = "Flight Plan"

// ✅ Good: Localized string
let title = String(localized: "Flight Plan", bundle: .module, comment: "Route planning title")
```

### SwiftUI Text

SwiftUI `Text` is automatically localized for literal strings, but NOT for variables:

```swift
// ✅ Automatically localized
Text("Save")

// ❌ Not localized (variable)
let str = "Save"
Text(str)

// ✅ Variable that is localized
let str = String(localized: "Save", bundle: .module, comment: "Save button")
Text(str)
```

### Objective-C in Swift Packages

```objective-c
// ✅ Good: NSLocalizedString works with .xcstrings
NSLocalizedString(@"Light", @"Light emitter category")
```

## What to Check

1. **Strings are localized** — No bare string literals for user-facing text
2. **Bundle specified** — Must use `bundle: .module` for package resources
3. **Comment provided** — Helps translators understand context

## Exceptions

- Log messages and debug output
- Analytics event names and parameters
- Internal identifiers and keys
- String literals in tests

## GitHub Comment

```
This user-facing string should be localized. See the [Swift Package Localization Guide](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/Localization/LocalizingSwiftPackages.md). A claude skill is available `/localize`.
```