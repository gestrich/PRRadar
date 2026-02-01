---
description: Strings used outside method scope should be defined as reusable constants.
category: clarity
applies_to:
  file_extensions: [".swift", ".m", ".mm"]
---

# String Constants

Strings that have meaning beyond the local method scope should be defined as constants in a reusable location, not inline at call sites.

## Requirements

### Define Strings as Constants

When a string represents a key, identifier, or value that applies outside the method's scope, define it as a constant:

```swift
// ❌ Bad: String defined at call site
UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

// ✅ Good: String defined as a constant
UserDefaults.standard.set(true, forKey: UserDefaultsKey.hasCompletedOnboarding)
```

```objc
// ❌ Bad: String defined at call site
[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"hasCompletedOnboarding"];

// ✅ Good: String defined as a constant
[NSUserDefaults.standardUserDefaults setBool:YES forKey:FFMUserDefaultsKeyHasCompletedOnboarding];
```

### When to Use Constants

Strings should be constants when they:

1. **Are used in multiple places** — Any string used more than once
2. **Represent keys** — UserDefaults keys, dictionary keys, notification names, cache keys
3. **Are API contracts** — JSON keys, URL paths, header names
4. **Have meaning outside the method** — The string's value matters to other code or systems

### When Inline Strings Are Acceptable

Inline strings are fine when they:

- Are purely local to the method with no external meaning
- Are user-facing strings (which should use localization instead)
- Are log messages or debug descriptions

## Defining String Constants

### Swift

Use a caseless enum to namespace related constants:

```swift
private enum UserDefaultsKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let lastSyncDate = "lastSyncDate"
}
```

For notification names, extend `Notification.Name`:

```swift
extension Notification.Name {
    static let userDidLogOut = Notification.Name("userDidLogOut")
}
```

### Objective-C

Define constants in the implementation file with `static NSString * const` for file-private constants:

```objc
// In .m file (file-private)
static NSString * const kHasCompletedOnboarding = @"hasCompletedOnboarding";
static NSString * const kLastSyncDate = @"lastSyncDate";
```

For constants shared across files, declare in the header and define in the implementation:

```objc
// In .h file
extern NSString * const FFMUserDefaultsKeyHasCompletedOnboarding;
extern NSString * const FFMUserDefaultsKeyLastSyncDate;

// In .m file
NSString * const FFMUserDefaultsKeyHasCompletedOnboarding = @"hasCompletedOnboarding";
NSString * const FFMUserDefaultsKeyLastSyncDate = @"lastSyncDate";
```

For notification names:

```objc
// In .h file
extern NSNotificationName const FFMUserDidLogOutNotification;

// In .m file
NSNotificationName const FFMUserDidLogOutNotification = @"FFMUserDidLogOutNotification";
```

## What to Check

When reviewing code with string literals:

1. **Repeated strings** — Same string appearing in multiple places
2. **Key-value access** — Strings used as keys for UserDefaults, dictionaries, notifications
3. **API strings** — JSON keys, URL components, header names

## GitHub Comment

```
This string has meaning outside this method's scope. Consider defining it as a constant in a reusable location to avoid duplication and make refactoring easier.
```
