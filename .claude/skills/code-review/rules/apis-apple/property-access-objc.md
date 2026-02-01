---
description: Ensures proper property and ivar access patterns in Objective-C implementation files.
documentation: https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/BestPractices/ObjectiveCBestPractices/ObjectiveCBestPractices.md
category: api-usage
applies_to:
  file_extensions: [".m", ".mm"]
---

# Objective-C Property Access

Proper property access patterns ensure safety, maintainability, and correct behavior of custom accessors.

## Avoid Pointer Access Syntax (`->`)

The `->` operator is C/C++ syntax for accessing members through a pointer. In Objective-C, avoid using `self->_property` unless working with C++ code (in `.mm` files).

Using `->` on a nil pointer will crash, whereas property access on nil safely returns nil.

```objective-c
// ❌ Bad: Pointer access syntax
self->_property = value;
NSString *name = self->_name;

// ✅ Good: Property access
self.property = value;
NSString *name = self.name;
```

Only use `->` when interfacing with C++ structs or when explicitly required by C++ interop.

## Direct Ivar Access (`_var`) Is Limited to Specific Contexts

Direct ivar access using the underscore syntax (`_var`) should **only** be used in:

1. **`init` methods** — Avoid triggering accessors before the object is fully initialized
2. **`dealloc`** — Avoid triggering accessors on a partially deallocated object
3. **Custom getters/setters** — When implementing the accessor itself

Using property accessors (`self.var`) ensures that any custom getter/setter logic, KVO notifications, or side effects are properly triggered. Direct ivar access bypasses all of this.

### In Regular Methods

```objective-c
// ❌ Bad: Direct ivar access in regular methods
- (void)updateDisplay {
    _label.text = _currentValue;
}

- (void)refreshData {
    NSString *name = _userName;
    _statusLabel.hidden = _isLoading;
}

// ✅ Good: Property access in regular methods
- (void)updateDisplay {
    self.label.text = self.currentValue;
}

- (void)refreshData {
    NSString *name = self.userName;
    self.statusLabel.hidden = self.isLoading;
}
```

### In Init Methods (Direct Access Allowed)

```objective-c
// ✅ Correct: Direct ivar access in init
- (instancetype)init {
    if (self = [super init]) {
        _name = @"Default";
        _count = 0;
        _items = [[NSMutableArray alloc] init];
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name {
    if (self = [super init]) {
        _name = [name copy];
    }
    return self;
}
```

### In Dealloc (Direct Access Allowed)

```objective-c
// ✅ Correct: Direct ivar access in dealloc
- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
```

### In Custom Accessors (Direct Access Allowed)

```objective-c
// ✅ Correct: Direct ivar access in custom getter/setter
- (NSString *)fullName {
    return [NSString stringWithFormat:@"%@ %@", _firstName, _lastName];
}

- (void)setCount:(NSInteger)count {
    if (_count != count) {
        _count = count;
        [self updateCountDisplay];
    }
}
```

## What to Check

When reviewing implementation file changes:

1. **No `->` syntax** — Flag any use of `self->_property` outside of `.mm` files with C++ interop
2. **Ivar access context** — Direct `_var` access should only appear in `init*`, `dealloc`, or custom accessor methods
3. **Regular methods use properties** — All other methods should use `self.property` syntax

## GitHub Comment

```
Direct ivar access (`_property`) generally should only be used in `init`, `dealloc`, or custom accessors. In regular methods, use property access to ensure custom accessors, KVO & atomicity are respected.

See [Objective-C Best Practices](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/BestPractices/ObjectiveCBestPractices/ObjectiveCBestPractices.md)
```
