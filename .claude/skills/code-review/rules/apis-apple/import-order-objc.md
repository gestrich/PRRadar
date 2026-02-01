---
description: Ensures Objective-C module imports (@import) are alphabetically ordered and placed above header imports (#import).
documentation: https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/BestPractices/ObjectiveCBestPractices/ObjectiveCBestPractices.md
category: api-usage
applies_to:
  file_extensions: [".m", ".mm", ".h"]
---

# Objective-C Import Order

Module imports (`@import`) should be organized alphabetically and placed in a separate section above header imports (`#import`).

## Requirements

### Section Order

Imports should be organized in this order:

1. **Module imports** (`@import`) — alphabetically ordered
2. **Header imports** (`#import`) — typically grouped by category

```objective-c
// ❌ Bad: Module imports mixed with header imports, not alphabetical
#import "MyClass.h"
@import UIKit;
#import <Foundation/Foundation.h>
@import CoreLocation;

// ✅ Good: Module imports first, alphabetically ordered
@import CoreLocation;
@import UIKit;

#import <Foundation/Foundation.h>
#import "MyClass.h"
```

### Alphabetical Ordering

Module imports must be in case-insensitive alphabetical order:

```objective-c
// ❌ Bad: Not alphabetical
@import MapKit;
@import CoreData;
@import UIKit;
@import AVFoundation;

// ✅ Good: Alphabetically ordered
@import AVFoundation;
@import CoreData;
@import MapKit;
@import UIKit;
```

### Separation

Keep a blank line between the module imports section and the header imports section:

```objective-c
// ✅ Good: Clear separation
@import CoreLocation;
@import UIKit;

#import <Foundation/Foundation.h>
#import "FFLocationService.h"
```

## What to Check

When reviewing import changes in Objective-C files:

1. **Module imports above headers** — All `@import` statements should appear before any `#import` statements
2. **Alphabetical order** — Module imports should be in alphabetical order (case-insensitive)
3. **Section separation** — Blank line between module imports and header imports

## GitHub Comment

```
Module imports (`@import`) should be placed above header imports and in alphabetical order.

See [Objective-C Best Practices](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/BestPractices/ObjectiveCBestPractices/ObjectiveCBestPractices.md)
```
