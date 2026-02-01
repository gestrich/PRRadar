---
description: Ensures newly added user-facing strings in the FFM target are properly localized using .strings files.
documentation: https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/Localization/LocalizingFFMTarget.md
category: api-usage
applies_to:
  file_patterns: ["ffm/**/*.swift", "ffm/**/*.m", "ffm/**/*.mm"]
---

# Localization (FFM Target)

All newly added user-facing strings in `ffm/` and `ffm/libraries/` must be localized using `NSLocalizedString` or `NSLocalizedStringFromTable` with `.strings` files.

## Requirements

### Swift

```swift
// ❌ Bad: Bare string literal
label.text = "Save"

// ✅ Good: Localized string
label.text = NSLocalizedString("MyFeature.Button.Save", comment: "Save button")

// ✅ Good: With table name for specific strings file
let title = NSLocalizedString("View.Title.MyFeature", tableName: "ViewNames", comment: "")
```

### Objective-C

```objective-c
// ❌ Bad: Bare string literal
self.title = @"Settings";

// ✅ Good: Localized string
self.title = NSLocalizedString(@"MyFeature.Title.Settings", @"Settings screen title");

// ✅ Good: With table name for specific strings file
self.title = NSLocalizedStringFromTable(@"View.Title.MyFeature", @"ViewNames", @"");
```

## Strings File Selection

| Code Location | Strings File | Usage |
|---------------|--------------|-------|
| `ffm/libraries/Checklist/` | `FFMCL_Localizable` | `tableName: "FFMCL_Localizable"` |
| `ffm/libraries/CustomContent/` | `FFMACM_Localizable` | `tableName: "FFMACM_Localizable"` |
| `ffm/libraries/Logbook/` | `LogbookUIStrings` | `tableName: "LogbookUIStrings"` |
| `ffm/libraries/PlacesKit/` | `PlacesKitUIStrings` | `tableName: "PlacesKitUIStrings"` |
| View/tab titles | `ViewNames` | `tableName: "ViewNames"` |
| Other general UI | `Localizable` | No `tableName` needed |

## What to Check

1. **Strings are localized** — No bare string literals for user-facing text
2. **Correct strings file** — Aspirational frameworks use their own table names
3. **Descriptive keys** — Keys follow naming conventions (e.g., `Feature.Element.Action`)

## Exceptions

- Log messages and debug output
- Analytics event names and parameters
- Internal identifiers and dictionary keys
- String literals in tests

## GitHub Comment

```
 New user-facing string should be localized. See the [FFM Target Localization Guide](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/Localization/LocalizingFFMTarget.md). A claude skill is available `/localize`.
```
