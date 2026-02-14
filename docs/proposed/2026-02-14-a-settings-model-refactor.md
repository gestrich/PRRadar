# Settings Model Refactor

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer placement, dependency flow |
| `swift-app-architecture:swift-swiftui` | Model composition, child-to-parent propagation, Observable patterns |
| `swift-testing` | Test style guide for new use case and model tests |

## Background

Settings management currently lives directly in `AppModel` — it holds a `SettingsService`, exposes `settings: AppSettings`, and has CRUD methods (`addConfiguration`, `removeConfiguration`, `updateConfiguration`, `setDefault`). This violates several architectural conventions:

1. **No use cases for settings** — AppModel calls SettingsService directly, bypassing the Features layer. The architecture requires that multi-step operations go through use cases so both CLI and GUI share the same logic.
2. **No SettingsModel** — Settings state is mixed into AppModel rather than owned by a dedicated child model. The model composition pattern calls for child models that own their slice of state.
3. **CLI duplicates logic** — `ConfigCommand` and `resolveConfig()` create raw `SettingsService()` instances rather than going through shared use cases.
4. **Views reach through AppModel** — `SettingsView` and `ContentView` access `appModel.settings` and call `appModel.addConfiguration()` instead of talking to a dedicated settings model.

The refactor introduces:
- **SettingsModel** — an `@Observable` child model owned by AppModel
- **Settings use cases** — in the Features layer, shared by GUI and CLI
- **AppModel subscription** — AppModel observes SettingsModel changes via `AsyncStream`
- **CLI parity** — CLI commands use the same use cases

### Current data flow
```
Views → AppModel → SettingsService → JSON
CLI   → SettingsService → JSON (duplicated)
```

### Target data flow
```
Views → SettingsModel → Use Cases → SettingsService → JSON
                │
                └── observeChanges() → AppModel (reacts to config changes)

CLI   → Use Cases → SettingsService → JSON
```

### Key files affected
- `Sources/apps/MacApp/Models/AppModel.swift` — remove settings CRUD, add SettingsModel property
- `Sources/apps/MacApp/UI/SettingsView.swift` — use SettingsModel instead of AppModel
- `Sources/apps/MacApp/UI/ContentView.swift` — read configs from settingsModel
- `Sources/apps/MacCLI/Commands/ConfigCommand.swift` — use settings use cases
- `Sources/apps/MacCLI/PRRadarMacCLI.swift` — resolveConfig uses LoadSettingsUseCase
- `PRRadar/PRRadarApp.swift` — construct SettingsModel, inject into AppModel

## Phases

## - [x] Phase 1: Settings Use Cases

**Skills to read**: `swift-app-architecture:swift-architecture` (layer placement, use case patterns)

Add use cases to the Features layer that encapsulate settings operations. Each takes `SettingsService` as a constructor dependency.

**New files** in `Sources/features/PRReviewFeature/usecases/`:

| Use Case | Method | What it does |
|----------|--------|--------------|
| `LoadSettingsUseCase` | `execute() -> AppSettings` | Calls `SettingsService.load()` |
| `SaveConfigurationUseCase` | `execute(config:settings:isNew:) throws -> AppSettings` | Adds or updates a config, saves, returns updated settings |
| `RemoveConfigurationUseCase` | `execute(id:settings:) throws -> AppSettings` | Removes config, reassigns default, saves, returns updated settings |
| `SetDefaultConfigurationUseCase` | `execute(id:settings:) throws -> AppSettings` | Sets default, saves, returns updated settings |

Pattern notes:
- Match existing use case style in this project: `Sendable` structs with `execute()` methods
- The mutating use cases accept the current `AppSettings`, apply the mutation, persist via `SettingsService.save()`, and return the new `AppSettings`. This keeps the load-mutate-save cycle atomic from the caller's perspective.
- `SettingsService` already has the mutation helpers (`addConfiguration`, `removeConfiguration`, `setDefault`), so use cases call those plus `save()`.

**Completed**: No Package.swift changes needed — `PRReviewFeature` already depends on `PRRadarConfigService`. `SaveConfigurationUseCase` includes a `SaveConfigurationError` for the case where an update targets a non-existent config ID.

## - [ ] Phase 2: SettingsModel

**Skills to read**: `swift-app-architecture:swift-swiftui` (model-composition.md, model-state.md)

Create `SettingsModel` as an `@Observable @MainActor` class in the Apps layer.

**New file**: `Sources/apps/MacApp/Models/SettingsModel.swift`

Key behaviors:
- Holds `private(set) var settings: AppSettings` as the single source of truth
- Injected with all four use cases via `init`
- Self-initializes: calls `LoadSettingsUseCase` on `init` to populate settings
- Exposes CRUD methods: `addConfiguration(_:)`, `updateConfiguration(_:)`, `removeConfiguration(id:)`, `setDefault(id:)` — each calls the appropriate use case and assigns the returned `AppSettings` to `settings`
- Implements **child-to-parent propagation** via `observeChanges() -> AsyncStream<AppSettings>` factory method (per model-composition.md pattern). Uses a `continuations` dictionary so multiple subscribers each get their own stream.

## - [ ] Phase 3: AppModel Integration

**Skills to read**: `swift-app-architecture:swift-swiftui` (model-composition.md — parent/child, child-to-parent propagation)

Refactor `AppModel` to use `SettingsModel` as a child model.

Changes to `Sources/apps/MacApp/Models/AppModel.swift`:
- Remove `private let settingsService: SettingsService`
- Remove `var settings: AppSettings`
- Remove `addConfiguration()`, `removeConfiguration()`, `updateConfiguration()`, `setDefault()`, `persistSettings()`
- Add `let settingsModel: SettingsModel`
- Change `init` to accept `SettingsModel` instead of constructing `SettingsService`
- Subscribe to `settingsModel.observeChanges()` in `init` via a `Task` — when settings change, the subscription can react if needed (e.g., if the active config was removed or modified)

Changes to `PRRadar/PRRadarApp.swift`:
- Construct `SettingsService` → use cases → `SettingsModel` → `AppModel`
- Inject `settingsModel` into environment alongside `appModel` so views can access it directly

## - [ ] Phase 4: View Updates

**Skills to read**: `swift-app-architecture:swift-swiftui` (dependency-injection.md, view-state.md)

Update views to use `SettingsModel` instead of `AppModel` for settings access.

Changes to `Sources/apps/MacApp/UI/SettingsView.swift`:
- Replace `let appModel: AppModel` with `@Environment(SettingsModel.self) var settingsModel`
- All CRUD calls go through `settingsModel` directly: `settingsModel.addConfiguration()`, `.removeConfiguration()`, etc.
- Read `settingsModel.settings.configurations` instead of `appModel.settings.configurations`

Changes to `Sources/apps/MacApp/UI/ContentView.swift`:
- Add `@Environment(SettingsModel.self) private var settingsModel`
- Config sidebar reads `settingsModel.settings.configurations`
- The `.task` that restores selection reads from `settingsModel.settings`
- Settings sheet passes `settingsModel` (or SettingsView reads it from environment)
- `selectConfig()` stays on AppModel since it creates `AllPRsModel` — that's an app-layer concern

## - [ ] Phase 5: CLI Updates

**Skills to read**: `swift-app-architecture:swift-architecture` (CLI data flow pattern)

Update CLI commands to use settings use cases.

Changes to `Sources/apps/MacCLI/Commands/ConfigCommand.swift`:
- `ListCommand.run()` uses `LoadSettingsUseCase` instead of raw `SettingsService().load()`
- Add new subcommands: `AddCommand`, `RemoveCommand`, `SetDefaultCommand` that use the corresponding use cases. This gives CLI parity with the GUI.

Changes to `Sources/apps/MacCLI/PRRadarMacCLI.swift`:
- `resolveConfig()` uses `LoadSettingsUseCase` instead of `SettingsService().load()`
- Add `ConfigCommand` subcommands to the `subcommands` array if needed

Note: CLI commands construct use cases directly (no SettingsModel needed — per architecture, CLI uses use cases directly since there's no observable state).

## - [ ] Phase 6: Validation

**Skills to read**: `swift-testing`

Verify correctness at every level.

**Build check:**
- `cd PRRadarLibrary && swift build` — must compile cleanly

**Unit tests** — new tests in `Tests/`:
- `LoadSettingsUseCaseTests` — verifies load returns persisted settings
- `SaveConfigurationUseCaseTests` — verifies add/update persists correctly, first config becomes default
- `RemoveConfigurationUseCaseTests` — verifies removal and default reassignment
- `SetDefaultConfigurationUseCaseTests` — verifies default flag toggling
- `SettingsModelTests` — verifies CRUD methods update `settings` property and that `observeChanges()` yields on mutation

**Integration check:**
- `swift test` — all existing tests still pass
- Run CLI: `swift run PRRadarMacCLI config list --config test-repo` — still works
- Build and launch MacApp: verify settings gear button opens SettingsView, add/edit/delete configs work, config sidebar updates reactively
