---
description: Ensures Objective-C header files have proper nullability annotations for Swift interoperability and API clarity.
documentation: https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/ObjectiveC/Nullability/Nullability.md
category: correctness
applies_to:
  file_extensions: [".h"]
---

# Nullability in Header Files (.h)

Nullability annotations in header files are critical for Swift interoperability and API clarity.

## Requirements

### All Declarations

All new APIs **must** be annotated with nullability — whether in new files or when adding new properties/methods to existing files. Do **not** use the suppression pragma in new files.

```objective-c
// ❌ Bad: Missing nullability
@interface MyService : NSObject
@property (nonatomic, strong) NSString *name;
- (NSString *)fetchData:(NSNumber *)identifier;
@end

// ✅ Good: Explicit nullability on all declarations
@interface MyService : NSObject
@property (nonatomic, strong, nullable) NSString *name;
- (nullable NSString *)fetchData:(nonnull NSNumber *)identifier;
@end
```

### Existing Header Files

When adding new APIs to an existing header file without nullability annotations, choose one approach:

1. **Annotate all APIs** in the file (existing and new) — preferred
2. **Annotate only new APIs** and suppress warnings for legacy code:

```objective-c
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

@interface LegacyService : NSObject

- (NSString *)existingMethod;  // Legacy, unannotated
- (nonnull NSString *)newMethod;  // New, annotated

@end

#pragma clang diagnostic pop
```

Do not add the suppression pragma unless you are adding new APIs to a file with existing unannotated APIs.

## Do Not Use NS_ASSUME_NONNULL

Do **not** use `NS_ASSUME_NONNULL_BEGIN` / `NS_ASSUME_NONNULL_END`. Marking APIs as nonnull by default is a dangerous assumption when unwrapping in Swift. Always use explicit annotations on each property and method.

## Choosing the Right Keyword

### Use `nonnull` / `nullable`

For simple property and parameter declarations:

```objective-c
@property (nonatomic, copy, nullable) NSString *title;
- (nullable NSString *)lookupByID:(nonnull NSNumber *)identifier;
```

### Use `_Nonnull` / `_Nullable`

Required when the pointer type is hidden inside:
- Typedefs
- Generics
- Block types
- Pointer-to-pointer values

```objective-c
// Typedef
typedef NSString *MyString;
@property (nonatomic, strong) MyString _Nullable aliasedName;

// Generics
@property (nonatomic, strong, nonnull) NSArray<NSString * _Nullable> *items;

// Block types
@property (nonatomic, copy, nullable) void (^ _Nullable completionHandler)(BOOL success);

// Pointer-to-pointer
- (BOOL)fetchData:(NSData * _Nullable * _Nonnull)outData error:(NSError * _Nullable * _Nullable)outError;
```

## Initializer Return Types

Init methods also **must always** have nullability specified on the return type. This includes `-init`, `-initWith*`, and any custom initializers.

```objective-c
// ❌ Bad: Missing nullability on init return type
- (instancetype)init;
- (instancetype)initWithName:(NSString *)name;
+ (instancetype)layerWithSource:(FFSource *)source;

// ✅ Good: Explicit nullability on init return type
- (nonnull instancetype)init;
- (nonnull instancetype)initWithName:(nonnull NSString *)name;
- (nullable instancetype)initWithName:(nullable NSString *)name;  // If init can fail
+ (nullable instancetype)layerWithSource:(nonnull FFSource *)source;
```

**Guidelines for init return nullability:**
- Use `nonnull` when the initializer always succeeds
- Use `nullable` when the initializer can return `nil` (failable initializers)
- Factory methods (`+layerWith*`, `+serviceWith*`) are often `nullable` since they may fail

## What to Check

When reviewing header file changes:

1. **All declarations annotated** — methods, properties, and constants must have nullability
2. **No NS_ASSUME_NONNULL** — explicit annotations required
3. **Correct keyword usage** — `nullable`/`nonnull` for simple cases, `_Nullable`/`_Nonnull` for wrapped pointers
4. **Suppression pragma only when needed** — only in existing files with legacy unannotated APIs
5. **Init methods annotated** — all initializers must have nullability on return type

## GitHub Comment

```
This property needs a nullability annotation. See [Nullability Guide](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/ObjectiveC/Nullability/Nullability.md)
```
