# SwiftCLI: Stdin Piping and Line-Buffered Streaming

## Background

PRRadar's `ClaudeBridgeClient` bypasses `CLIClient` entirely and uses raw `Foundation.Process` because SwiftCLI lacks two common CLI capabilities: **stdin piping** (writing data to a process's standard input) and **line-buffered streaming** (reading stdout one line at a time via `bytes.lines` instead of raw data chunks via `readabilityHandler`).

This plan adds both capabilities to the SwiftCLI library as general-purpose features, then migrates PRRadar to use them — eliminating all manual `Process` management from `ClaudeBridgeClient`.

### What's being added to SwiftCLI

| Capability | CLI terminology | Current state | After |
|---|---|---|---|
| Stdin piping | Writing to a process's stdin fd | Not supported | `stdin: Data?` parameter on `execute()` and `stream()` |
| Line-buffered streaming | Reading stdout line-by-line | Only raw chunks via `readabilityHandler` | New `streamLines()` methods using `bytes.lines` |
| Line parser | Transforming each stdout line into a typed value | N/A | `CLILineParser` protocol + `streamLines(parser:)` |
| Throwing stream | `AsyncThrowingStream` that throws on non-zero exit | Only non-throwing `AsyncStream<StreamOutput>` | `streamLines()` returns `AsyncThrowingStream` |

## Phases

## - [x] Phase 1: Add stdin piping to existing SwiftCLI APIs

**Repo:** `/Users/bill/Developer/personal/SwiftCLI`

Add `stdin: Data? = nil` parameter to these methods in [CLIClient.swift](../../PRRadarLibrary/.build/checkouts/SwiftCLI/Sources/CLISDK/CLIClient.swift):

- `execute(command:arguments:...)` (line 125)
- `stream(command:arguments:...)` (line 206)
- Internal `runProcess()` (line 504) — the core implementation
- Internal `executeProcess()` (line 468) — pass-through
- Internal `streamProcess()` (line 806) — pass-through

**Implementation in `runProcess()`:** When `stdin` is provided and `inheritIO` is false:
1. Create a `Pipe()` and assign to `process.standardInput` before `process.run()`
2. After `process.run()`, write the data and close the writing end:
   ```swift
   stdinPipe.fileHandleForWriting.write(stdinData)
   stdinPipe.fileHandleForWriting.closeFile()
   ```

**Files:**
- Modify: `Sources/CLISDK/CLIClient.swift`

**Completed:** All 5 methods updated with `stdin: Data? = nil` parameter. Stdin pipe is created before `process.run()`, data is written and writing end closed after `process.run()`. Only applies when `inheritIO` is false (when `inheritIO` is true, the parent process stdin is inherited instead). All 104 existing tests pass.

## - [x] Phase 2: Add CLILineParser protocol and streamLines() methods

**Repo:** `/Users/bill/Developer/personal/SwiftCLI`

### New file: `Sources/CLISDK/CLILineParser.swift`

Following the pattern of `CLIOutputParser` (which parses complete stdout after a command finishes), create `CLILineParser` (which parses each line as it arrives):

```swift
public protocol CLILineParser<Output>: Sendable {
    associatedtype Output: Sendable
    func parse(line: String) throws -> Output?  // nil = skip this line
}
```

Built-in implementations:
- `PassthroughLineParser` — yields all non-empty lines as `String`
- `JSONLineParser<T: Decodable>` — decodes each line as JSON, skips decode failures

### New internal method: `runLineBufferedProcess()`

A new private method in `CLIClient` alongside `runProcess()`. Uses `bytes.lines` instead of `readabilityHandler`:
- Stdout: `for try await line in stdoutPipe.fileHandleForReading.bytes.lines`
- Stderr: still captured via `readabilityHandler`
- Each stdout line broadcast to global/client `CLIOutputStream` as `StreamOutput.stdout(text: line + "\n")`
- After loop: `process.waitUntilExit()`, check exit code, throw `CLIClientError.executionFailed` or finish

### New public methods on `CLIClient`

```swift
// Raw lines
func streamLines(
    command:, arguments:, workingDirectory:, environment:,
    printCommand:, stdin:, output:
) -> AsyncThrowingStream<String, Error>

// Parsed lines
func streamLines<P: CLILineParser>(
    command:, arguments:, workingDirectory:, environment:,
    printCommand:, stdin:, parser:, output:
) -> AsyncThrowingStream<P.Output, Error>

// Typed command variants
func streamLines<C: CLICommand>(_ command:, ...) -> AsyncThrowingStream<String, Error>
func streamLines<C: CLICommand, P: CLILineParser>(_ command:, parser:, ...) -> AsyncThrowingStream<P.Output, Error>
```

**Files:**
- Create: `Sources/CLISDK/CLILineParser.swift`
- Modify: `Sources/CLISDK/CLIClient.swift`

**Completed:** Created `CLILineParser` protocol with `PassthroughLineParser` and `JSONLineParser<T>` built-in implementations. Added `runLineBufferedProcess()` as a private async method that uses `bytes.lines` for stdout and `readabilityHandler` for stderr. Added 4 public `streamLines()` variants (raw + parsed, untyped + typed command). The raw-string variants delegate to the parsed variants via `PassthroughLineParser`. The typed command variants extract `commandLine` and delegate to the untyped variants. All return `AsyncThrowingStream` — throws `CLIClientError.executionFailed` on non-zero exit. All 104 existing tests pass.

## - [x] Phase 3: SwiftCLI tests

**Repo:** `/Users/bill/Developer/personal/SwiftCLI`

Create `Tests/CLISDKTests/StreamLinesTests.swift`:
- `streamLines()` with `echo` — verify lines arrive individually
- `streamLines()` with `stdin` data piped to `cat` — verify round-trip
- `streamLines(parser:)` with a test `CLILineParser` that parses/skips
- `streamLines()` throws on non-zero exit (e.g., `false` command)
- `execute()` with `stdin` data piped to `cat`
- `PassthroughLineParser` and `JSONLineParser` unit tests

**Files:**
- Create: `Tests/CLISDKTests/StreamLinesTests.swift`

**Completed:** Created `StreamLinesTests.swift` with 16 tests across 3 suites: `streamLines Tests` (6 tests covering echo output, stdin+cat round-trip, custom parser skip behavior, non-zero exit error throwing, and exit code verification), `PassthroughLineParser Tests` (3 tests for non-empty, empty, and whitespace-only lines), and `JSONLineParser Tests` (7 tests for valid JSON decoding, invalid JSON, empty lines, wrong schema, custom decoder, and end-to-end integration with `streamLines`). All 120 tests pass (104 existing + 16 new). Note: `CLIClient` is an actor, so all `streamLines()` calls require `await`.

## - [x] Phase 4: Push SwiftCLI to main

Commit all SwiftCLI changes and push to `main`. PRRadar depends on `SwiftCLI` via `.package(url: "https://github.com/gestrich/SwiftCLI.git", branch: "main")`.

**Completed:** All three commits from Phases 1-3 are on `origin/main`: `fb5acb8` (stdin piping), `51e002a` (CLILineParser + streamLines), `2d77772` (tests). All 120 tests pass (104 existing + 16 new).

## - [x] Phase 5: Migrate PRRadar's ClaudeBridgeClient

**Repo:** `/Users/bill/Developer/personal/PRRadar`

### Update SwiftCLI dependency

Run `swift package update SwiftCLI` to pull the latest from main.

### Add `BridgeMessageParser` conforming to `CLILineParser`

Convert the existing `BridgeMessage` failable init (lines 25-46 of [ClaudeBridgeClient.swift](PRRadarLibrary/Sources/services/PRRadarCLIService/ClaudeBridgeClient.swift)) into a `CLILineParser` that returns `BridgeStreamEvent?`.

### Rewrite `ClaudeBridgeClient` to use `CLIClient`

Replace raw `Process` management with:
```swift
cliClient.streamLines(
    command: "python3", arguments: [bridgeScriptPath],
    environment: PRRadarEnvironment.build(),
    printCommand: false, stdin: requestData,
    parser: BridgeMessageParser()
)
```

This eliminates:
- Manual `Process` creation and pipe setup (lines 139-154)
- Manual `bytes.lines` iteration (line 156)
- Manual exit code checking (lines 177-185)
- `resolvePythonPath()` entirely (lines 197-242) — `CLIClient.resolveCommand()` handles this

`ClaudeBridgeClient` changes from a standalone struct to one that takes a `CLIClient` dependency.

### Update callers in Features layer

Two call sites construct `ClaudeBridgeClient`:
- [EvaluateUseCase.swift:87](PRRadarLibrary/Sources/features/PRReviewFeature/usecases/EvaluateUseCase.swift#L87) — `ClaudeBridgeClient(bridgeScriptPath: config.bridgeScriptPath)`
- [FetchRulesUseCase.swift:50](PRRadarLibrary/Sources/features/PRReviewFeature/usecases/FetchRulesUseCase.swift#L50) — same

Both need to pass a `CLIClient` instance. Per the architecture guide, Features can depend on SDKs (CLIClient lives in the CLISDK). These use cases can create a `CLIClient()` locally or receive one via init — follow whichever pattern the other use cases use (e.g., `GitOperationsService` takes `CLIClient` via init at `GitHubServiceFactory:41`).

**Files:**
- Modify: `PRRadarLibrary/Sources/services/PRRadarCLIService/ClaudeBridgeClient.swift`
- Modify: `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/EvaluateUseCase.swift`
- Modify: `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/FetchRulesUseCase.swift`

**Completed:** Updated SwiftCLI dependency to `2d77772` (latest main with stdin piping and streamLines). Created `BridgeMessageParser` conforming to `CLILineParser` that converts each JSON-line into a `BridgeStreamEvent`. Rewrote `ClaudeBridgeClient` to use `CLIClient.streamLines(parser:)` — eliminated all manual `Process` management, pipe setup, `bytes.lines` iteration, exit code checking, and the entire `resolvePythonPath()` method (46 lines). `ClaudeBridgeClient.init` now requires a `cliClient: CLIClient` parameter. Updated both callers (`EvaluateUseCase`, `FetchRulesUseCase`) to pass `CLIClient()` and added `CLISDK` dependency to `PRReviewFeature` target in `Package.swift`. `CLIClientError` is caught and wrapped as `ClaudeBridgeError.bridgeFailed` to preserve the existing error contract. All 313 tests pass.

## - [ ] Phase 6: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions:

**For SwiftCLI changes:**
- Verify `CLILineParser` follows the same public API patterns as `CLIOutputParser`
- Verify `streamLines()` follows the same internal flow as `stream()` (prepareCommand → run process → broadcast to output streams)

**For PRRadar Swift changes (`PRRadarLibrary/`):**
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Verify layer dependencies: `ClaudeBridgeClient` is in Services, depends on CLISDK — valid (Services → SDKs)
- Verify Features layer callers don't violate dependency rules
- Compare the commits against the conventions; fix any violations

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the architecture repo
4. Evaluate changes against each skill's conventions
5. Fix any violations found

## - [ ] Phase 7: Validation

### Automated tests
```bash
# SwiftCLI
cd /Users/bill/Developer/personal/SwiftCLI && swift test

# PRRadar
cd /Users/bill/Developer/personal/PRRadar/PRRadarLibrary && swift build && swift test
```

### End-to-end verification
```bash
cd /Users/bill/Developer/personal/PRRadar/PRRadarLibrary
swift run PRRadarMacCLI diff 1 --config test-repo
```

### Success criteria
- All SwiftCLI tests pass (existing + new `StreamLinesTests`)
- All PRRadar tests pass (230 tests in 34 suites)
- `ClaudeBridgeClient` no longer imports or uses `Foundation.Process` directly
- CLI commands that invoke the bridge still produce correct output
