# Mac App Architecture Restructure

## Background

The `pr-radar-mac` SwiftPM app was developed as a quick proof-of-concept without following the 4-layer architecture principles defined in the `swift-app-architecture` skills. Currently, the app has business logic (CLI execution, environment setup, output parsing) mixed directly into `ContentView.swift`, uses multiple independent `@State` variables instead of enum-based state, and has no Features or Services layers.

As the app grows to support all 7 agent commands (currently only Phase 1/Diff is wired up), this structure won't scale. Restructuring now — while the app is small (3 source files) — is the ideal time.

We'll use **targets within a single Package.swift** (not separate packages) to enforce layer boundaries, following the pattern established in `swift-lambda-sample`.

### Current Structure
```
Sources/
├── apps/MacApp/
│   ├── main.swift              ← App entry point (clean)
│   └── UI/ContentView.swift    ← UI + business logic mixed (182 lines)
└── sdks/PRRadarMacSDK/
    └── PRRadar.swift           ← CLI command definitions (clean)
```

### Target Structure
```
Sources/
├── apps/MacApp/                ← App layer: @Observable models, SwiftUI views, entry point
├── features/PRReviewFeature/   ← Features layer: UseCases orchestrating multi-step workflows
├── services/
│   ├── PRRadarCLIService/      ← Services layer: CLI execution and output parsing
│   └── PRRadarConfigService/   ← Services layer: Environment config, data paths
└── sdks/PRRadarMacSDK/         ← SDK layer: CLI command type definitions (already exists)
```

### Architecture Principles Applied
- **Depth Over Width**: App calls one model, model calls one use case, use case orchestrates
- **Zero Duplication**: Features/Services are UI-agnostic; a future CLI app could reuse them
- **Use Cases Orchestrate**: `FetchDiffUseCase` owns the multi-step flow (build command → execute → parse output)
- **SDKs Are Stateless**: `PRRadarMacSDK` remains a `Sendable` struct library of command definitions
- **@Observable at App Layer Only**: Only `MacApp` target contains `@Observable` models
- **Enum-Based State**: Replace scattered `@State` booleans with a proper state enum
- **Configuration at App Layer**: Configuration services created at app startup and injected downward — use cases never load config themselves

## Phases

## - [x] Phase 1: Create Services Layer — Configuration + CLI Services

Extract configuration and CLI execution infrastructure from `ContentView.swift` into two new services targets.

**Completed.** Both service targets compile and the full project builds successfully.

### `PRRadarConfigService` — Configuration & Data Paths

**New target:** `PRRadarConfigService` at `Sources/services/PRRadarConfigService/`

Following the configuration skill pattern, this service centralizes environment and path configuration.

**Files created:**
- `PRRadarConfigService/PRRadarEnvironment.swift` — Builds the environment dictionary (PATH with venv, Homebrew, system paths + HOME). Extracted from `ContentView.prradarEnvironment`. Accepts `venvBinPath` as a parameter — does not derive it from `#filePath`.
- `PRRadarConfigService/DataPathsService.swift` — Type-safe enum-based paths for PRRadar output directories. Maps phase names to directory paths (e.g., `.pullRequest` → `{outputDir}/{prNumber}/phase-1-pull-request/`). Auto-creates directories if needed.
- `PRRadarConfigService/PRRadarConfig.swift` — Struct holding resolved configuration values: `venvBinPath`, `repoPath`, `outputDir`. Created at the App layer, passed into use cases. Includes computed properties for `prradarPath`, `resolvedOutputDir`, and `absoluteOutputDir`.

**Dependencies:** None (Foundation only)

**Key design decisions:**
- No dependencies on other targets — pure configuration, no CLI or SDK imports
- `PRRadarConfig` is a plain `Sendable` struct — holds resolved values, not raw settings
- `DataPathsService` follows the enum-based path pattern from the configuration skill
- `PRRadarEnvironment` receives the venv path as input — the App layer resolves where it is

### `PRRadarCLIService` — CLI Execution

**New target:** `PRRadarCLIService` at `Sources/services/PRRadarCLIService/`

**Files created:**
- `PRRadarCLIService/PRRadarCLIRunner.swift` — `Sendable` struct that executes prradar CLI commands. Wraps `CLIClient` creation, argument construction (including the `--output-dir` insertion logic), and execution. Returns structured results (exit code, stdout, stderr) rather than mutating UI state. Generic over `CLICommand where C.Program == PRRadar` to constrain to PRRadar commands only.
- `PRRadarCLIService/CLIResult.swift` — Struct with `exitCode`, `output`, `errorOutput`, and computed `isSuccess`.
- `PRRadarCLIService/OutputFileReader.swift` — Reads output files from phase output directories using `DataPathsService`. Returns `[String]` file paths.

**Dependencies:** `PRRadarMacSDK`, `PRRadarConfigService`, `CLISDK`

**Package.swift changes:**
- Add `PRRadarConfigService` library target with path `Sources/services/PRRadarConfigService` (no dependencies)
- Add `PRRadarCLIService` library target with path `Sources/services/PRRadarCLIService`
  - Dependencies: `PRRadarMacSDK`, `PRRadarConfigService`, `.product(name: "CLISDK", package: "SwiftCLI")`

**Key design decisions:**
- `PRRadarCLIRunner` is a struct (not class), `Sendable`, stateless
- Methods accept `PRRadarConfig` and `PRRadarEnvironment` outputs — receives resolved config, never loads it
- Returns `CLIResult` — no UI concerns
- `OutputFileReader` uses `DataPathsService` to resolve output directories

**Technical notes:**
- `PRRadarCLIRunner.execute` is generic over `CLICommand` but constrained to `C.Program == PRRadar` — ensures only PRRadar commands can be executed through the runner
- `CLIResult` is a separate type from CLISDK's `ExecutionResult` to decouple from the external dependency at the service boundary
- `PRRadarConfig.absoluteOutputDir` handles tilde expansion and relative-to-repo-path resolution, centralizing path logic that was previously inline in `ContentView.runPhase1()`

## - [x] Phase 2: Create Features Layer — `PRReviewFeature` Target

Create use cases that orchestrate the CLI service calls into user-facing workflows.

**Completed.** PRReviewFeature target compiles and the full project builds successfully.

**New target:** `PRReviewFeature` at `Sources/features/PRReviewFeature/`

**Files created:**
- `PRReviewFeature/models/FetchDiffProgress.swift` — Enum with three progress states: `.running`, `.completed(files:)`, `.failed(error:)`. All cases are `Sendable`.
- `PRReviewFeature/usecases/FetchDiffUseCase.swift` — `Sendable` struct that accepts `PRRadarCLIRunner`, `PRRadarConfig`, and environment at init. The `execute(prNumber:)` method returns an `AsyncThrowingStream<FetchDiffProgress, Error>` that yields `.running`, then executes `PRRadar.Agent.Diff` via the CLI runner, reads output files via `OutputFileReader`, and yields `.completed(files:)` or `.failed(error:)`.

**Dependencies:** `PRRadarCLIService`, `PRRadarConfigService`, `PRRadarMacSDK`

**Package.swift changes:**
- Added `PRReviewFeature` library target with path `Sources/features/PRReviewFeature`
- Dependencies: `PRRadarCLIService`, `PRRadarConfigService`, `PRRadarMacSDK`

**Key design decisions:**
- Use `StreamingUseCase` pattern (not plain `UseCase`) since CLI execution is async with progress
- The use case does NOT know about SwiftUI, `@Observable`, or any UI types
- Use cases receive resolved configuration via init — they never load config themselves (per configuration skill)
- Future agent commands (rules, evaluate, report, etc.) become additional use cases in this same target

**Technical notes:**
- `FetchDiffUseCase` is a plain `Sendable` struct — no protocols or abstractions since there's only one implementation
- The `AsyncThrowingStream` wraps a `Task` internally to bridge the sync continuation API with async CLI execution
- Input validation (empty repo path, PR number) is left to the App layer since `PRRadarConfig` already requires these values at construction time

## - [ ] Phase 3: Restructure App Layer — Enum-Based State + @Observable Model

Refactor `ContentView.swift` to follow Model-View architecture with enum-based state.

**Files to modify:**
- `Sources/apps/MacApp/UI/ContentView.swift` — Slim down to pure view code that observes a model

**Files to create:**
- `Sources/apps/MacApp/Models/PRReviewModel.swift` — `@Observable @MainActor` class that:
  - Owns an enum state: `.idle`, `.running(logs: [String])`, `.completed(files: [String], logs: [String])`, `.failed(error: String, logs: [String])`
  - Holds `@AppStorage` persistent settings (repoPath, prNumber, outputDir)
  - Has a `runDiff()` method that creates and streams from `FetchDiffUseCase`
  - Replaces the scattered `@State` variables (`isRunning`, `outputFiles`, `errorMessage`, `logs`)

**`main.swift` changes — Configuration initialized at App layer:**
- Create `PRRadarConfig` with resolved venv path (derived from bundle/known location)
- Create `PRRadarEnvironment` from the config
- Pass config into `PRReviewModel` via init
- Model stored as `@State` in the App struct, injected into views via `.environment()`

```swift
@main
struct PRRadarMacApp: App {
    @State private var model: PRReviewModel

    init() {
        let config = PRRadarConfig(venvBinPath: /* resolved at app layer */)
        let environment = PRRadarEnvironment.build(config: config)
        _model = State(initialValue: PRReviewModel(
            config: config,
            environment: environment
        ))
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 700, height: 600)
    }
}
```

**ContentView changes:**
- Remove all `@State` properties
- Remove `venvBinPath`, `prradarEnvironment`, `runPhase1()` — all moved to lower layers
- Receive model from environment
- View body reads state from model's enum and renders accordingly
- Button action simply calls `model.runDiff()`

**Package.swift changes:**
- Update `MacApp` target dependencies: add `PRReviewFeature`, `PRRadarConfigService`, keep `CLISDK`
- Remove direct `PRRadarMacSDK` dependency from MacApp (accessed through Features)

**Key design decisions:**
- Model is `@Observable` (not `@State` in view) — follows MV architecture
- Enum state eliminates impossible states (e.g., `isRunning = true` AND `errorMessage != nil`)
- **Configuration created at App layer, injected into model** — per configuration skill, the App layer owns initialization
- Model receives resolved config; it never creates configuration services itself
- `@AppStorage` stays in the model for user preferences (repoPath, prNumber, outputDir) — these are UI-layer persistence, distinct from app configuration

## - [ ] Phase 4: Update Package.swift Dependency Graph

Finalize the Package.swift to enforce layer boundaries through target dependencies.

**Target dependency graph:**
```
MacApp (App Layer)
  ├── PRReviewFeature (Features Layer)
  │    ├── PRRadarCLIService (Services Layer)
  │    │    ├── PRRadarConfigService (Services Layer — no deps)
  │    │    ├── PRRadarMacSDK (SDK Layer)
  │    │    └── CLISDK (External)
  │    ├── PRRadarConfigService
  │    └── PRRadarMacSDK
  └── PRRadarConfigService (for config initialization at App layer)
```

**Full Package.swift target list:**
```swift
// SDK Layer
.target(
    name: "PRRadarMacSDK",
    dependencies: [.product(name: "CLISDK", package: "SwiftCLI")],
    path: "Sources/sdks/PRRadarMacSDK"
),

// Services Layer — Configuration (Foundation-only, no other target deps)
.target(
    name: "PRRadarConfigService",
    path: "Sources/services/PRRadarConfigService"
),

// Services Layer — CLI Execution
.target(
    name: "PRRadarCLIService",
    dependencies: [
        .target(name: "PRRadarMacSDK"),
        .target(name: "PRRadarConfigService"),
        .product(name: "CLISDK", package: "SwiftCLI"),
    ],
    path: "Sources/services/PRRadarCLIService"
),

// Features Layer
.target(
    name: "PRReviewFeature",
    dependencies: [
        .target(name: "PRRadarCLIService"),
        .target(name: "PRRadarConfigService"),
        .target(name: "PRRadarMacSDK"),
    ],
    path: "Sources/features/PRReviewFeature"
),

// App Layer
.executableTarget(
    name: "MacApp",
    dependencies: [
        .target(name: "PRReviewFeature"),
        .target(name: "PRRadarConfigService"),
        .product(name: "CLISDK", package: "SwiftCLI"),
    ],
    path: "Sources/apps/MacApp",
    swiftSettings: [.unsafeFlags(["-parse-as-library"])]
),
```

**Verification:** Build must succeed with `swift build` — the compiler enforces that no target imports a module it doesn't declare as a dependency.

## - [ ] Phase 5: Validation

**Build verification:**
- `cd pr-radar-mac && swift build` must succeed with no errors
- Verify each target compiles independently (no circular dependencies)

**Architecture compliance checks:**
- `PRRadarMacSDK` imports only `CLISDK` and Foundation — no app/feature/service imports
- `PRRadarCLIService` imports only `PRRadarMacSDK`, `CLISDK`, Foundation — no SwiftUI or app imports
- `PRReviewFeature` imports only `PRRadarCLIService`, `PRRadarMacSDK` — no SwiftUI or `@Observable`
- `MacApp` is the only target with `import SwiftUI` and `@Observable`

**Functional verification:**
- Run the app, enter repo path / PR number / output dir
- Click "Run Phase 1" — should produce same behavior as before (fetch diff, show files, show logs)
- Verify `@AppStorage` persistence still works (quit and relaunch, fields should be populated)

**State management verification:**
- While running: UI shows progress indicator, button disabled
- On success: UI shows output files list and logs
- On failure: UI shows error message and logs
- Cannot be in both "running" and "error" state simultaneously (enum enforces this)
