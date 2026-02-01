---
description: Ensures Objective-C implementation files have proper nullability annotations on all declarations.
documentation: https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/ObjectiveC/Nullability/Nullability.md
category: correctness
applies_to:
  file_extensions: [".m", ".mm"]
---

# Nullability in Implementation Files (.m)

Nullability annotations in implementation files ensure internal consistency and allow the compiler to warn when violating the nullability contract.

## Requirements

### All Declarations

All new APIs **must** be annotated with nullability — whether in new files or when adding new properties/methods to existing files.

```objective-c
// ❌ Bad: Missing nullability
@interface MyService ()
@property (nonatomic, strong) NSString *cachedValue;
- (NSString *)internalHelper:(NSString *)input;
@end

// ✅ Good: Explicit nullability on all declarations
@interface MyService ()
@property (nonatomic, strong, nullable) NSString *cachedValue;
- (nonnull NSString *)internalHelper:(nonnull NSString *)input;
@end
```

### Consistency with Header

Implementation method signatures should match the nullability declared in the corresponding header file.

## Choosing the Right Keyword

### Use `nonnull` / `nullable`

For simple property and parameter declarations:

```objective-c
@property (nonatomic, strong, nullable) NSString *cachedValue;
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

## Method Nullability Examples

### Instance Methods

```objective-c
// ❌ Bad: Missing nullability on return type and parameters
- (NSString *)formatValue:(NSNumber *)value;
- (void)updateWithData:(NSData *)data completion:(void (^)(BOOL))handler;

// ✅ Good: All return types and parameters annotated
- (nullable NSString *)formatValue:(nonnull NSNumber *)value;
- (void)updateWithData:(nonnull NSData *)data completion:(nullable void (^)(BOOL))handler;
```

### Class Methods and Factory Methods

```objective-c
// ❌ Bad: Missing nullability
+ (instancetype)serviceWithConfiguration:(NSDictionary *)config;
+ (NSArray *)availableOptions;

// ✅ Good: Annotated factory and class methods
+ (nullable instancetype)serviceWithConfiguration:(nonnull NSDictionary *)config;
+ (nonnull NSArray *)availableOptions;
```

### Initializers

Init methods also **must always** have nullability specified on the return type, even for simple `-init` overrides. This includes `-init`, `-initWith*`, and any custom initializers.

```objective-c
// ❌ Bad: Missing nullability on init return type and parameters
- (instancetype)init;
- (instancetype)initWithName:(NSString *)name delegate:(id<MyDelegate>)delegate;

// ✅ Good: Annotated init method with return type and parameters
- (nonnull instancetype)init;
- (nonnull instancetype)initWithName:(nonnull NSString *)name delegate:(nullable id<MyDelegate>)delegate;
- (nullable instancetype)initWithConfiguration:(nonnull NSDictionary *)config;  // If init can fail
```

**Guidelines for init return nullability:**
- Use `nonnull` when the initializer always succeeds (most common)
- Use `nullable` when the initializer can return `nil` (failable initializers)
- Even parameterless `-init` overrides require nullability on the return type

### Methods with Multiple Parameters

```objective-c
// ❌ Bad: Some parameters missing nullability
- (BOOL)saveItem:(NSString *)item
        toFolder:(NSString *)folder
           error:(NSError **)error;

// ✅ Good: All parameters annotated including pointer-to-pointer
- (BOOL)saveItem:(nonnull NSString *)item
        toFolder:(nullable NSString *)folder
           error:(NSError * _Nullable * _Nullable)error;
```

### Methods with Block Parameters

```objective-c
// ❌ Bad: Block and block parameters missing nullability
- (void)fetchDataWithCompletion:(void (^)(NSData *data, NSError *error))completion;

// ✅ Good: Block nullability and block parameter nullability specified
- (void)fetchDataWithCompletion:(nullable void (^)(NSData * _Nullable data, NSError * _Nullable error))completion;
```

### Delegate and Protocol Methods

```objective-c
// ❌ Bad: Missing nullability in protocol method implementation
- (void)service:(MyService *)service didReceiveResponse:(NSDictionary *)response;

// ✅ Good: Matches protocol declaration with proper nullability
- (void)service:(nonnull MyService *)service didReceiveResponse:(nullable NSDictionary *)response;
```

## What to Check

When reviewing implementation file changes:

1. **All declarations annotated** — methods and properties in class extensions must have nullability
2. **Correct keyword usage** — `nullable`/`nonnull` for simple cases, `_Nullable`/`_Nonnull` for wrapped pointers
3. **Consistency with header** — implementation should match header annotations
4. **Method return types** — every method returning an object pointer needs nullability
5. **All parameters** — each object pointer parameter requires annotation
6. **Block parameters** — both the block itself and its parameters need nullability
7. **Init methods annotated** — all initializers (including `-init`) must have nullability on return type

## GitHub Comment

```
This property should have a nullability annotation.

See [Nullability Guide](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/ObjectiveC/Nullability/Nullability.md)
```
