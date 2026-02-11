# PRRadar XCUITest Notes

App-specific navigation patterns, accessibility identifiers, and tips for XCUITest automation of the PRRadar MacApp.

## UI Layout

PRRadar uses a three-column `NavigationSplitView`:

```
┌──────────────┬───────────────────┬──────────────────────────────────┐
│  Column 1    │    Column 2       │         Column 3                 │
│  Config      │    PR List        │         Detail View              │
│  Sidebar     │                   │                                  │
│              │                   │   ┌─────────────────────────┐   │
│  test-repo ◄─┤  PR #1          │   │ PR Header               │   │
│  my-config   │  PR #2   ◄───────┤   │ Pipeline Status Bar     │   │
│              │  PR #3           │   │ [Summary|Diff|Report]   │   │
│              │                   │   │ Phase Content           │   │
│              │                   │   └─────────────────────────┘   │
└──────────────┴───────────────────┴──────────────────────────────────┘
```

### Column 1: Config Sidebar
- Lists saved repo configurations (e.g., `test-repo`)
- Select a config to load its PRs

### Column 2: PR List
- Shows PRs for the selected config
- Filter bar at top: days lookback, state filter, refresh, analyze all, add new PR
- Select a PR to view its detail

### Column 3: Detail View
- **PR Header**: PR number, title, author
- **Pipeline Status Bar**: Phase nodes showing completion status
- **Navigation tabs**: Summary, Diff, Report
- **Toolbar buttons**: Settings (gear), Refresh (arrow.clockwise), Analyze (sparkles), Folder, Safari

## Navigation Steps for Common Views

**PR Summary view** (default after selecting a PR):
1. Select config → 2. Select PR → Summary is shown by default

**Diff view**:
1. Select config → 2. Select PR → 3. Tap "Diff" in pipeline status

**Report view**:
1. Select config → 2. Select PR → 3. Tap "Report" in pipeline status

**Settings sheet**:
Tap the gear toolbar button → `app.buttons["Manage configurations"]`

## Known Accessibility Identifiers

| Identifier Pattern | Element Type | Location |
|---|---|---|
| `settingsButton` | Button | Toolbar |
| `refreshButton` | Button | Toolbar |
| `Manage configurations` | Button | Toolbar (gear icon) |
| `configRow_<name>` | Cell | Config Sidebar |
| `test-repo` | Cell | Config Sidebar |
| `prRow_<number>` | Cell | PR List |
| `PR #<number>` | Cell | PR List |
| `phaseButton_<phase>` | Button | Pipeline Status Bar |
| `Summary` | Button/StaticText | Pipeline tabs |
| `Diff` | Button/StaticText | Pipeline tabs |
| `Report` | Button/StaticText | Pipeline tabs |

## PRRadar-Specific Tips

- The `done` command will report a timeout from the Python CLI — this is expected. The test exits before writing a "completed" status. Check the xcodebuild output for "TEST EXECUTE SUCCEEDED" to confirm clean shutdown.
- Always kill stale `PRRadarMac` processes before starting a test: `pkill -f "PRRadarMac" 2>/dev/null; sleep 2`
- After exiting the test, kill orphaned app processes: `pkill -f "PRRadarMac" 2>/dev/null`
- The Xcode project (`PRRadar.xcodeproj`) already has the `XCUITestControl` package configured as a local SPM dependency and the `PRRadarMacUITests` target linked to it. No additional package setup is needed.
- The `xcode-sim-automation` package is shared and reusable — when improvements are identified (new commands, bug fixes, better error handling), edit the package directly and commit the changes.

## Screenshot Test Patterns

When creating automated screenshot tests for PRRadar views:

### Test File Template
- Place files in `PRRadarMacUITests/`
- Name: `ScreenshotTest_<ViewName>.swift`
- Use the `captureHierarchy(name:)` helper to save UI state at each navigation step
- Use the `findTappable(_:)` helper that tries Button → StaticText → Cell automatically
- Use `XCTAssertTrue` at every navigation step (never use `if` statements for navigation)

### Common Navigation Code
```swift
// Select a config
let config = findTappable("test-repo")
XCTAssertTrue(config.exists, "Config should exist")
config.tap()
sleep(2)

// Select a PR
let pr = findTappable("PR #1")
XCTAssertTrue(pr.exists, "PR should exist")
pr.tap()
sleep(2)

// Navigate to a phase tab
let report = findTappable("Report")
XCTAssertTrue(report.exists, "Report tab should exist")
report.tap()
sleep(2)
```

### Settings Sheet
```swift
let settingsButton = app.buttons["Manage configurations"]
XCTAssertTrue(settingsButton.waitForExistence(timeout: 5.0), "Settings button should exist")
settingsButton.tap()
```
