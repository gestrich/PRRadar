---
description: Ensures Objective-C code uses lightweight generics on collection types for type safety and Swift interoperability.
documentation: https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/BestPractices/ObjectiveCBestPractices/ObjectiveCBestPractices.md
category: api-usage
applies_to:
  file_extensions: [".h", ".m", ".mm"]
---

# Objective-C Generics

Use lightweight generics on collection types (`NSArray`, `NSDictionary`, `NSSet`, etc.) to improve type safety and Swift interoperability.

## Requirements

Generics **must** be used on all collection types in new code:
- Properties
- Method parameters
- Method return types
- Local variables

## Properties

```objective-c
// ❌ Bad: Untyped collections
@property (nonatomic, copy) NSArray *airports;
@property (nonatomic, strong) NSDictionary *routesByIdentifier;
@property (nonatomic, strong) NSSet *selectedWaypoints;

// ✅ Good: Typed collections
@property (nonatomic, copy) NSArray<FFAirport *> *airports;
@property (nonatomic, strong) NSDictionary<NSString *, FFRoute *> *routesByIdentifier;
@property (nonatomic, strong) NSSet<FFWaypoint *> *selectedWaypoints;
```

## Method Signatures

Apply generics to both parameters and return types.

```objective-c
// ❌ Bad: Untyped parameters and return types
- (NSArray *)fetchAirportsInRegion:(FFRegion *)region;
- (void)updateRoutes:(NSDictionary *)routes;
- (NSDictionary *)groupFlightsByDate:(NSArray *)flights;

// ✅ Good: Typed parameters and return types
- (NSArray<FFAirport *> *)fetchAirportsInRegion:(FFRegion *)region;
- (void)updateRoutes:(NSDictionary<NSString *, FFRoute *> *)routes;
- (NSDictionary<NSDate *, NSArray<FFFlight *> *> *)groupFlightsByDate:(NSArray<FFFlight *> *)flights;
```

## Local Variables

Use generics even for local variables to catch type errors at compile time.

```objective-c
// ❌ Bad: Untyped local variables
NSArray *results = [self fetchResults];
NSMutableArray *filtered = [NSMutableArray array];
NSDictionary *cache = @{};

// ✅ Good: Typed local variables
NSArray<FFResult *> *results = [self fetchResults];
NSMutableArray<FFResult *> *filtered = [NSMutableArray array];
NSDictionary<NSString *, FFCacheEntry *> *cache = @{};
```

## Nested Generics

For collections containing other collections, nest the generic parameters.

```objective-c
// ❌ Bad: Missing nested type parameters
@property (nonatomic, copy) NSDictionary *sectionedData;

// ✅ Good: Fully typed nested collections
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<FFDataItem *> *> *sectionedData;
```

## Combining with Nullability

When using generics with nullability annotations, use the underscore form (`_Nullable`/`_Nonnull`) inside the angle brackets.

```objective-c
@property (nonatomic, copy, nullable) NSArray<NSString *> *names;
@property (nonatomic, copy) NSArray<NSString * _Nullable> *optionalNames;
- (nullable NSArray<FFAirport *> *)fetchAirports;
```

## Common Collection Types

Apply generics to these Foundation types:
- `NSArray<ObjectType>` / `NSMutableArray<ObjectType>`
- `NSDictionary<KeyType, ValueType>` / `NSMutableDictionary<KeyType, ValueType>`
- `NSSet<ObjectType>` / `NSMutableSet<ObjectType>`
- `NSOrderedSet<ObjectType>` / `NSMutableOrderedSet<ObjectType>`
- `NSHashTable<ObjectType>`
- `NSMapTable<KeyType, ValueType>`
- `NSCache<KeyType, ValueType>`
- `NSEnumerator<ObjectType>`

## What to Check

When reviewing Objective-C code:

1. **All collections typed** — properties, parameters, return types, and local variables
2. **Nested types specified** — collections of collections are fully typed

## GitHub Comment

```
This collection type should use generics for type safety. Example: `NSArray<MyType *> *` instead of `NSArray *`. See [Objective-C Best Practices](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/BestPractices/ObjectiveCBestPractices/ObjectiveCBestPractices.md)
```
