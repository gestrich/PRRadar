---
description: Ensures Swift import statements are alphabetically ordered.
documentation: https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/BestPractices/SwiftBestPractices/SwiftBestPractices.md
category: api-usage
applies_to:
  file_extensions: [".swift"]
---

# Swift Import Order

Import statements in Swift files should be alphabetically ordered for consistency and easier scanning.

## Requirements

### Alphabetical Ordering

All import statements must be in case-insensitive alphabetical order:

```swift
// ❌ Bad: Not alphabetical
import UIKit
import Foundation
import SwiftUI
import Combine

// ✅ Good: Alphabetically ordered
import Combine
import Foundation
import SwiftUI
import UIKit
```

### Testable Imports

`@testable import` statements should be ordered alphabetically by module name along with regular imports:

```swift
// ❌ Bad: @testable imports grouped separately
import Foundation
import XCTest

@testable import MyModule
@testable import MyOtherModule

// ✅ Good: All imports alphabetical by module name
import Foundation
@testable import MyModule
@testable import MyOtherModule
import XCTest
```

## What to Check

When reviewing import changes in Swift files:

1. **Alphabetical order** — All import statements should be in alphabetical order by module name (case-insensitive)
2. **Testable imports inline** — `@testable import` sorted alphabetically with other imports

## GitHub Comment

```
Package import statements should be in alphabetical order. This makes imports easier to scan and prevents duplicates.

See [Swift Best Practices](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/BestPractices/SwiftBestPractices/SwiftBestPractices.md)
```
