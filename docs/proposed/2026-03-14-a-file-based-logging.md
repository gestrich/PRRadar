## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules — determines where the logging service lives |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns — how to inject the logger into models/views |

## Background

Bill wants structured, file-based logging in PRRadar so that external scripts and AI tooling can programmatically read app events. He currently has a bespoke `debugLog()` function in `PRModel.swift` that writes to `/tmp/prradar-debug.log`. The goal is to replace this with something more native and maintainable.

### Research Summary

Apple's `os.Logger` writes exclusively to the unified logging system — there is no built-in way to route it to a file. The newer APIs (2024–2025) added no custom backend/destination support. `OSLogStore` can read logs back, but it's a pull model requiring polling.

The best fit for this use case is **Apple's `swift-log` package** (`apple/swift-log`) — it's maintained by the Swift Server Working Group, provides a `LogHandler` protocol for custom backends, and supports `MultiplexLogHandler` to fan out to multiple destinations. A file-writing `LogHandler` is straightforward to implement (~30 lines) without pulling in a third-party file logger dependency.

### Approach: `swift-log` with a custom `FileLogHandler`

- Add `apple/swift-log` as a dependency
- Create a simple `FileLogHandler` that appends JSON lines to a file
- Bootstrap in the App/CLI entry points
- Use `Logger` from `swift-log` at call sites
- Log file location: `~/Library/Logs/PRRadar/prradar.log` (standard macOS convention, accessible to scripts)
- JSON-lines format for easy parsing by AI tooling

### V1 Scope — ~10 log events

Focus on the main pipeline lifecycle events in the Mac app:
1. App launch
2. Analysis started (with PR number)
3. Phase started (diff/prepare/analyze/report)
4. Phase completed (with success/failure)
5. Phase skipped
6. Evaluation task started (with rule name)
7. Evaluation task completed (with result)
8. Comment submitted
9. Analysis completed (overall)
10. Error occurred (with description)

## Phases

## - [x] Phase 1: Add `swift-log` dependency and create `FileLogHandler`

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: LoggingSDK placed in SDK layer with no internal dependencies (only swift-log); stateless Sendable struct per SDK conventions

**Skills to read**: `swift-app-architecture:swift-architecture`

1. Add `apple/swift-log` to `Package.swift` dependencies
2. Create a new SDK target: `LoggingSDK` at `Sources/sdks/LoggingSDK/`
   - `FileLogHandler.swift` — implements `LogHandler` protocol, appends JSON lines to a file
   - Each log line: `{"timestamp":"ISO8601","level":"info","label":"PRRadar.PRModel","message":"...","metadata":{...}}`
   - Handle file creation, append, and basic rotation (e.g., truncate if > 10MB)
   - Log path: `~/Library/Logs/PRRadar/prradar.log`
3. The SDK target depends on `swift-log` only (follows SDK layer rules — no internal dependencies)

## - [x] Phase 2: Bootstrap logging in App and CLI entry points

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Bootstrap in entry points only (App layer); shared helper in LoggingSDK keeps both targets DRY; CLI uses static let closure for one-time initialization before any subcommand runs

**Skills to read**: `swift-app-architecture:swift-swiftui`

1. Add `LoggingSDK` dependency to `MacApp` and `PRRadarMacCLI` targets in `Package.swift`
2. In the MacApp entry point, call `LoggingSystem.bootstrap` with the `FileLogHandler`
3. In the CLI entry point, do the same
4. Create `Logger` instances at call sites using `Logger(label: "PRRadar.<ComponentName>")`

## - [x] Phase 3: Add ~10 log events in `PRModel.swift`

**Skills used**: none (straightforward replacement)
**Principles applied**: Replaced bespoke file-writing debugLog() with swift-log Logger; used .info for lifecycle events, .warning for skipped phases, .error for failures; structured metadata for machine-parseable fields

1. Replace the bespoke `debugLog()` calls with `swift-log` `Logger` calls (there are ~12 `debugLog()` calls covering `runAnalysis`, `runPrepare`, and `runAnalyze` — these become the initial log events)
2. Remove the `debugLogPath` and `debugLog()` function entirely
3. Add the V1 log events listed above, using appropriate log levels:
   - `.info` for lifecycle events (analysis started/completed, phase started/completed)
   - `.warning` for skipped phases
   - `.error` for failures
4. Use structured metadata where useful (e.g., `logger[metadataKey: "prNumber"] = "\(prNumber)"`)

## - [x] Phase 4: Validation

**Skills used**: `swift-testing`, `swift-app-architecture:swift-architecture`
**Principles applied**: Tests follow Arrange/Act/Assert with `#expect`; added LogReaderService in SDK layer (stateless Sendable), FetchLogsUseCase in Features layer, LogsCommand in Apps layer (I/O only); dedicated LoggingSDKTests test target

**Skills to read**: `swift-testing`

1. `swift build` — verify the package compiles with the new dependency
2. `swift test` — verify existing tests still pass
3. Write a unit test for `FileLogHandler` verifying:
   - It creates the log file if missing
   - It appends JSON-line entries
   - Each entry is valid JSON with expected fields (timestamp, level, label, message)
4. Manual check: run the Mac app, trigger an analysis, verify `~/Library/Logs/PRRadar/prradar.log` contains the expected log lines
