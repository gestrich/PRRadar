## Background

The PRRadar Mac app currently uses a traditional Xcode project (`PRRadarMac.xcodeproj`) with a separate Swift package (`PRRadarMacSDK/`). The swift-lambda-sample project demonstrates a superior approach: a single top-level `Package.swift` that defines all targets (sdks, services, features, apps) without any `.xcodeproj`. The Mac app runs as a SwiftPM executable target using the `@main` macro with `NSApplication.setActivationPolicy(.regular)` to appear in the Dock.

This plan transitions PRRadar's Mac app to match that exact structure. Since PRRadar is primarily a Python project, the Swift targets are limited to the SDK and Mac app — no services/features layers needed yet.

**Reference project:** `/Users/bill/Developer/personal/swift-lambda-sample`

### Target directory layout

```
PRRadar/
├── Package.swift                          # NEW — top-level SwiftPM manifest
├── Sources/
│   ├── sdks/
│   │   └── PRRadarMacSDK/
│   │       └── PRRadar.swift              # MOVED from PRRadarMacSDK/Sources/PRRadarMacSDK/
│   └── apps/
│       └── MacApp/
│           ├── main.swift                 # MODIFIED from PRRadarMac/PRRadarMac/PRRadarMacApp.swift
│           └── UI/
│               └── ContentView.swift      # MOVED from PRRadarMac/PRRadarMac/ContentView.swift
├── prradar/                               # Existing Python package (unchanged)
├── plugin/                                # Existing Claude plugin (unchanged)
├── tests/                                 # Existing Python tests (unchanged)
└── ... (existing files unchanged)
```

## Phases

## - [x] Phase 1: Create top-level Package.swift

Copy `Package.swift` from swift-lambda-sample, then strip it down for PRRadar. The PRRadar package only needs:

- **Package name:** `PRRadar`
- **Platform:** `.macOS(.v15)`
- **Swift tools version:** `6.2`
- **Dependencies:** SwiftCLI (same as current PRRadarMacSDK)
- **Targets:**
  1. `.target(name: "PRRadarMacSDK", ...)` — library at `Sources/sdks/PRRadarMacSDK`, depends on `CLISDK`
  2. `.executableTarget(name: "MacApp", ...)` — app at `Sources/apps/MacApp`, depends on `PRRadarMacSDK` and `CLISDK`, with `-parse-as-library` swift setting
- **Products:** One executable product: `MacApp`

Remove all swift-lambda-sample-specific targets (Lambda, CLI, AWS, Docker, etc.) and their dependencies.

**Completed.** Created top-level `Package.swift` with placeholder source files in `Sources/sdks/PRRadarMacSDK/` and `Sources/apps/MacApp/` so the build succeeds. Real source files will be moved in Phase 2.

## - [x] Phase 2: Create Sources directory structure and move files

Create the directory tree and move source files:

1. Create directories:
   - `Sources/sdks/PRRadarMacSDK/`
   - `Sources/apps/MacApp/UI/`

2. Move SDK source:
   - `PRRadarMacSDK/Sources/PRRadarMacSDK/PRRadar.swift` → `Sources/sdks/PRRadarMacSDK/PRRadar.swift`

3. Move app UI source:
   - `PRRadarMac/PRRadarMac/ContentView.swift` → `Sources/apps/MacApp/UI/ContentView.swift`

4. Create new `Sources/apps/MacApp/main.swift` based on the swift-lambda-sample pattern:
   - Copy swift-lambda-sample's `Sources/apps/MacApp/main.swift` as the starting template
   - Change struct name to `PRRadarMacApp` (or `MacAppMain` to match the reference)
   - Remove `model`/`environment` references (PRRadar doesn't have AppModel yet)
   - Keep `NSApplication.shared.setActivationPolicy(.regular)` and `activate(ignoringOtherApps:)` calls
   - Keep `.defaultSize(width: 700, height: 600)`
   - Wire up `ContentView()` in the `WindowGroup`

**Completed.** Replaced Phase 1 placeholders with real source files. `PRRadar.swift` moved to `Sources/sdks/PRRadarMacSDK/`, `ContentView.swift` copied to `Sources/apps/MacApp/UI/`, and `main.swift` updated with `PRRadarMacApp` struct using the reference project's `NSApplication` activation pattern. Note: `ContentView.swift` still has the old `#filePath` depth (3 levels) — Phase 3 will update it to 5 levels for the new location.

## - [ ] Phase 3: Update ContentView.swift for new file location

The `venvBinPath` computed property uses `#filePath` to navigate up to the repo root. Since the file moves from `PRRadarMac/PRRadarMac/ContentView.swift` (3 levels deep) to `Sources/apps/MacApp/UI/ContentView.swift` (5 levels deep), update the path calculation:

**Current** (3 `deletingLastPathComponent` calls):
```swift
URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // ContentView.swift → PRRadarMac/PRRadarMac/
    .deletingLastPathComponent() // → PRRadarMac/
    .deletingLastPathComponent() // → repo root
```

**New** (5 `deletingLastPathComponent` calls):
```swift
URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // ContentView.swift → UI/
    .deletingLastPathComponent() // → MacApp/
    .deletingLastPathComponent() // → apps/
    .deletingLastPathComponent() // → Sources/
    .deletingLastPathComponent() // → repo root
```

Also update the import — change `import PRRadarMacSDK` (unchanged, since the module name stays the same).

## - [ ] Phase 4: Update .gitignore for SwiftPM

Add SwiftPM build artifacts to `.gitignore`:

```
# Swift Package Manager
.build/
.swiftpm/
Package.resolved
```

The existing `build/` entry already covers the Python build directory but `.build/` is the SwiftPM-specific build directory.

## - [ ] Phase 5: Remove old Xcode project and separate package

Remove the files that are no longer needed:

1. Delete `PRRadarMac/` directory entirely (contains `.xcodeproj` and the old source files that have been moved)
2. Delete `PRRadarMacSDK/` directory entirely (its source has been moved to `Sources/sdks/`, its `Package.swift` is replaced by the top-level one)

## - [ ] Phase 6: Validation

1. **Build the package:** `swift build` from the repo root — should compile both targets
2. **Build MacApp specifically:** `swift build --product MacApp`
3. **Run MacApp:** `.build/debug/MacApp` — should launch with Dock icon and show the ContentView UI
4. **Open in Xcode:** `xed .` — verify Xcode can open the workspace and all targets are visible
5. **Verify Python is unaffected:** `python -m pytest tests/ -v` — existing Python tests should still pass
6. **Verify venvBinPath:** Confirm the `#filePath`-based path calculation resolves to the correct `.venv/bin` directory
