## Relevant Skills

| Skill | Description |
|-------|-------------|
| `pr-radar-add-rule` | Rule creation conventions and structure |
| `pr-radar-debug` | How to test rules via CLI |

## Background

The existing `service-locator-usage` experimental rule tells developers to inject dependencies instead of using `FFSL.shared`/`FFSLObjC.shared`. The messaging needs to be updated to:

1. Mention the **accessor pattern** as a minimum acceptable alternative when full DI isn't feasible
2. Explain that service locators represent **technical debt** and that removing direct usage improves **modularity and unit testability**
3. Reference the [shared services guide](https://github.com/example-org/example-ios/blob/develop/docs/shared-services.md) for the accessor pattern details

Two files need text updates:
- `/path/to/rules/service-locator-usage.md` — full rule description
- `/path/to/rules/check-service-locator-usage.sh` — inline violation messages

## Phases

## - [x] Phase 1: Update rule markdown

**Files to modify**: `/path/to/rules/service-locator-usage.md`

Replace the rule description and examples with updated text. Key changes:

**Title section (lines 15-19)** — replace with:

```markdown
# Service Locator Client Usage

Do not introduce new direct usage of `FFSL.shared` or `FFSLObjC.shared` to access services. Service locators represent technical debt — removing direct usage improves modularity and unit testability.

**Preferred:** Inject the needed service via an initializer parameter from at least one level above.

**Minimum acceptable:** If injection requires a risky legacy refactor, isolate the service locator behind a private accessor property so the rest of the class uses `self.<service>` instead of `FFSL.shared.<service>`. This makes dependencies explicit and simplifies future migration to dependency injection.

This rule specifically targets **client usage** — where code accesses a property or calls a method on a service obtained from the locator (e.g., `FFSL.shared.userService.currentUser`). It does not flag simple references that merely pass the locator or inject a service.

It also only flags usage in files that did **not** already reference that service locator, targeting genuinely new introductions rather than additions to existing legacy usage.
```

**Requirements section** — replace with:

```markdown
## Requirements

- New files must not use `FFSL.shared` or `FFSLObjC.shared` to call service methods or access service properties directly
- Preferred: inject dependencies via initializers
- At minimum: wrap service locator access in private accessor properties
```

**Examples section** — keep existing Swift DI and ObjC examples, add a new accessor pattern example between them:

```swift
// ⚠️ Acceptable when injection requires risky legacy refactor
class MyViewController: UIViewController {

    private var userService: UserService {
        FFSL.shared.userService
    }

    private var analyticsService: AnalyticsService {
        FFSL.shared.analyticsService
    }

    func viewDidLoad() {
        super.viewDidLoad()
        let user = userService.currentUser
        analyticsService.trackEvent("loaded")
    }
}
```

**What to Check section** — replace with:

```markdown
## What to Check

1. **No new direct client usage** — `FFSL.shared.service.something` or `[FFSLObjC.shared.service message]` should not appear in files that didn't already use that locator
2. **Services are injected** — pass dependencies through initializers when possible
3. **At minimum, use accessors** — if injection isn't feasible, wrap locator access in private computed properties so the class references `self.<service>` instead
4. **Injection site is acceptable** — using `FFSL.shared` at a parent/caller to provide a dependency to a child is an acceptable intermediate step
```

**GitHub Comment section** — replace with:

```
Service locators represent technical debt — removing direct usage improves modularity and unit testability. Please inject this service via an initializer parameter, or at minimum isolate it behind a private accessor property (e.g. `private var userService: UserService { FFSL.shared.userService }`) so the rest of the class uses `self.userService`. See the [shared services guide](https://github.com/example-org/example-ios/blob/develop/docs/shared-services.md).
```

## - [x] Phase 2: Update shell script messages

**Files to modify**: `/path/to/rules/check-service-locator-usage.sh`

Update the two `printf` comment strings (lines 56-57 and 63-64) from:

```
Avoid adding new service locator calls. Instead, inject the dependency. Injecting services improves testability and modularity. See the [shared services guide](...).
```

To:

```
Avoid adding new service locator calls. Service locators represent technical debt — removing direct usage improves modularity and unit testability. Please inject this dependency via an initializer, or at minimum isolate it behind a private accessor property. See the [shared services guide](...).
```

## - [x] Phase 3: Validation

Run the script against a test file to confirm it still detects violations and emits the updated message:

```bash
echo 'let x = FFSL.shared.userService.currentUser' > /tmp/test-sl.swift
bash /path/to/rules/check-service-locator-usage.sh /tmp/test-sl.swift
```

Verify the output contains the new message text about accessor patterns and technical debt.
