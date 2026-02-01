---
description: Ensures new code does not directly reference FFSL or FFSLObjC service locators.
documentation: https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/Architecture/SharedServices/shared-services.md
category: api-usage
applies_to:
  file_extensions: [".swift", ".m", ".mm"]
---

# Service Locator Usage

New code should not directly reference `FFSL.shared` or `FFSLObjC.shared`. Instead, dependencies should be injected via initializers from at least one level above.

## Requirements

This applies to:
- **New files**: Inject services through initializers
- **New code in existing files**: Inject new dependencies rather than adding direct service locator references

It is acceptable to use `FFSL`/`FFSLObjC` at the injection site (e.g., a parent class) to provide dependencies to a client. This is an intermediate step as service locators are removed. But the client itself must not directly reference the service locator.

### Swift

```swift
// ❌ Bad: Class directly references service locator
class FlightPlanService {
    func loadFlightPlan() {
        let user = FFSL.shared.userService.currentUser
    }
}

// ✅ Good: Class receives injected dependency
class FlightPlanService {
    private let userService: UserService

    init(userService: UserService) {
        self.userService = userService
    }

    func loadFlightPlan() {
        let user = userService.currentUser
    }
}

// At the injection site (parent, etc.) - this is OK:
let service = FlightPlanService(userService: FFSL.shared.userService)
```

### Objective-C

```objective-c
// ❌ Bad: Class directly references service locator
- (void)loadFlightPlan {
    FFUser *user = FFSLObjC.shared.userService.currentUser;
}

// ✅ Good: Class receives injected dependency
- (instancetype)initWithUserService:(UserService *)userService {
    self = [super init];
    if (self) {
        _userService = userService;
    }
    return self;
}

- (void)loadFlightPlan {
    FFUser *user = self.userService.currentUser;
}

// At the injection site - this is OK:
FlightPlanService *service = [[FlightPlanService alloc]
    initWithUserService:FFSLObjC.shared.userService];
```

## What to Check

1. **No FFSL/FFSLObjC in clients references** — New code should not call `FFSL.shared` or `FFSLObjC.shared` directly
2. **Service Locator services are injected** — Services should be passed via initializers
3. **Injection site is appropriate** — FFSL/FFSLObjC usage is only at the parent/caller level

## Exceptions

- Existing legacy code (see [service-locator-accessors](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/Architecture/ServiceLocatorAccessors/service-locator-accessors.md) for refactoring pattern)

## GitHub Comment

```
New code should not directly reference `FFSL.shared` or `FFSLObjC.shared`. Instead, inject this dependency from at least one level above. See the [Shared Services Guide](https://github.com/jeppesen-foreflight/ff-ios/blob/develop/FFMDevGuide/Sources/FFMDevGuide/Documentation.docc/Architecture/SharedServices/shared-services.md).
```
