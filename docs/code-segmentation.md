# Code Segmentation

Instructions for parsing diffs into logical code units for review.

## Overview

Each file's diff is parsed into logical **segments**. Every line of changed code must belong to exactly one segment. Segments are classified by type and change status.

## Segment Types

| Type | Description | Examples |
|------|-------------|----------|
| **imports** | Import/include statements | `#import`, `import`, `@import` |
| **interface** | Class/protocol/struct declarations | `@interface`, `@protocol`, `class`, `struct` |
| **extension** | Extensions/categories | `@interface Foo ()`, `extension Foo` |
| **properties** | Property declarations | `@property`, `var`, `let` at class level |
| **method** | Method/function implementations | `-methodName`, `func methodName()` |
| **initializer** | Init methods | `-init`, `init()`, `-initWith*` |
| **deinitializer** | Dealloc/deinit | `-dealloc`, `deinit` |
| **constants** | Constants/enums/macros | `static let`, `enum`, `#define` |
| **pragma** | Pragma marks and organization | `#pragma mark`, `// MARK:` |
| **other** | Code that doesn't fit above categories | Global variables, file-level code |

## Change Status

Each segment is marked with its change status:

| Status | Description | Diff Pattern |
|--------|-------------|--------------|
| **added** | New code | All lines are `+` in diff |
| **removed** | Deleted code | All lines are `-` in diff |
| **modified** | Changed code | Mix of `+` and `-` lines |

## Segmentation Rules

1. **Method boundaries**: A method segment starts at the method signature and ends at the closing brace
2. **Contiguous changes**: If multiple adjacent lines change within a method, they form one segment
3. **Context preservation**: Include enough context (2-3 lines) around changes to understand the segment
4. **No orphan lines**: Every changed line must belong to a segment

## Examples

### Swift Method (modified)

```diff
 func fetchUserData() async {
+    let result = await networkClient.fetch(userID)
+    self.userData = result
-    self.userData = nil
 }
```

Segment: `Method fetchUserData() (modified)`

### Objective-C Interface (added)

```diff
+@interface FFLayerManager : NSObject
+@property (nonatomic, strong) NSArray *layers;
+@end
```

Segment: `Interface FFLayerManager (added)`

### Swift Properties (modified)

```diff
 class UserService {
+    private var cache: [String: User] = [:]
     private let networkClient: NetworkClient
-    private var isLoading: Bool = false
```

Segment: `Properties (modified)`

### Import Statements (modified)

```diff
 import Foundation
+import Combine
-import RxSwift
```

Segment: `Imports (modified)`

## File Type Considerations

### Swift Files (`.swift`)

- Look for `func`, `var`, `let`, `class`, `struct`, `protocol`, `extension`, `enum`
- Method boundaries defined by matching braces
- Properties can be at class level or within extensions

### Objective-C Headers (`.h`)

- Look for `@interface`, `@protocol`, `@property`, method declarations (`-`, `+`)
- Interface ends at `@end`
- Properties typically grouped together

### Objective-C Implementation (`.m`)

- Look for `@implementation`, method implementations (`-`, `+`)
- `#pragma mark` for organization
- Implementation ends at `@end`

### JSON/Config Files

- Treat as single segment of type `other`
- Or segment by top-level keys if changes are isolated

## Segment Naming Convention

Name segments descriptively:

| Type | Naming Pattern | Example |
|------|----------------|---------|
| method | `Method methodName()` | `Method fetchUserData()` |
| interface | `Interface ClassName` | `Interface FFLayerManager` |
| extension | `Extension ClassName` | `Extension UserService` |
| properties | `Properties` or `Properties (ClassName)` | `Properties` |
| imports | `Imports` | `Imports` |
| initializer | `Initializer` or `Method init()` | `Initializer` |
| constants | `Constants` | `Constants` |
| other | Descriptive name | `Root object`, `Configuration` |
