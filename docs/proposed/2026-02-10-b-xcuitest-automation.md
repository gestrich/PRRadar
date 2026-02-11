# XCUITest Automation for PRRadar MacApp

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules — placement guidance for new test infrastructure |
| `swift-app-architecture:swift-swiftui` | SwiftUI patterns — needed when adding accessibility identifiers to views |

## Background

PRRadar has a SwiftUI MacApp for browsing PR diffs, reports, and evaluation outputs. Bill wants Claude to be able to interactively control this app — reading the UI hierarchy, tapping buttons, scrolling, typing text — the same way the iOS app at `/Users/bill/Developer/work/ios` does.

The reusable pieces have already been extracted into the `xcode-sim-automation` Swift package at `/Users/bill/Developer/personal/xcode-sim-automation`. This package provides:

- **`XCUITestControl` library** — 4 Swift source files (~590 lines total):
  - `InteractiveControlLoop` — polling loop that reads commands from `/tmp/xcuitest-command.json`, executes actions, writes hierarchy + screenshot
  - `InteractiveCommand` — Codable command model (action, target, targetType, index, status, etc.)
  - `InteractiveActionExecutor` — dispatches tap, scroll, type, wait, screenshot, adjust, pinch, done
  - `ElementLookup` — finds elements across types (button → staticText → textField → cell → slider → any)
- **Python CLI** (`Tools/xcuitest-control.py`) — Claude-friendly interface wrapping the file-based protocol
- **Two Claude skills** — `interactive-xcuitest` and `creating-automated-screenshots`

The Xcode project (`PRRadar.xcodeproj`) already has:
- `PRRadarMac` target — the app, depends on `MacApp` SPM library
- `PRRadarMacUITests` target — UI test bundle, already links `XCUITestControl` as a local SPM dependency
- Boilerplate test files (no `InteractiveControlLoop` usage yet)

**Key challenge**: The `xcode-sim-automation` package declares `platforms: [.iOS(.v17)]` but PRRadar is macOS. The XCUITest APIs are largely identical across platforms, so this is primarily a Package.swift change.

### Reference Implementation (iOS App)

If issues arise during implementation, reference the working iOS setup:
- **Skills**: `/Users/bill/Developer/work/ios/.claude/skills/interactive-xcuitest/SKILL.md` and `creating-automated-screenshots/SKILL.md`
- **Planning doc**: `/Users/bill/Developer/work/ios/docs/completed/2026-02-10-a-xcuitest-control-swift-package.md` — full extraction history
- **Multiple element matching fix**: `/Users/bill/Developer/work/ios/docs/proposed/fix-xcuitest-multiple-element-matching.md`
- **GitHub Actions CI**: `/Users/bill/Developer/work/ios/.github/workflows/xcuitest.yml` — CI setup for XCUITests (uses `xcode-ui-automation` Python package, not this one)
- The iOS app uses `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`; macOS uses `-destination 'platform=macOS'`

## - [x] Phase 1: Add macOS Platform Support to xcode-sim-automation

**Skills to read**: none

Update the `xcode-sim-automation` package at `/Users/bill/Developer/personal/xcode-sim-automation` to support macOS in addition to iOS.

**Tasks:**
- Edit `Package.swift` to change `platforms: [.iOS(.v17)]` to `platforms: [.iOS(.v17), .macOS(.v15)]`
- Review the 4 Swift source files for any iOS-only API usage:
  - `InteractiveControlLoop.swift` — uses `XCUIApplication`, `XCTest` — both available on macOS
  - `InteractiveCommand.swift` — pure Codable models, no platform-specific code
  - `InteractiveActionExecutor.swift` — uses `XCUIElement.tap()`, `swipeUp()`, `typeText()`, `adjust(toNormalizedSliderPosition:)`, `pinch(withScale:velocity:)` — all available on macOS, though `pinch` may behave differently
  - `ElementLookup.swift` — uses `XCUIElementQuery`, `XCUIElementTypeQueryProvider` — available on macOS
- Run `swift package dump-package` and `swift package resolve` to verify
- Cannot run `swift build` because the package links XCTest (which requires a test host), so validation is via dump-package

**Expected outcome**: Package resolves cleanly with both iOS and macOS platforms.

**Completed**: Bumped `swift-tools-version` from 5.9 to 6.0 (required because `.macOS(.v15)` is only available in PackageDescription 6.0+). All 4 source files reviewed — no iOS-only API usage found. All XCUITest APIs used (`tap()`, `swipeUp()`, `typeText()`, `pinch(withScale:velocity:)`, `coordinate(withNormalizedOffset:)`, `press(forDuration:thenDragTo:)`) are available on macOS. `swift package dump-package` and `swift package resolve` both pass.

## - [x] Phase 2: Wire Up InteractiveControlLoop in PRRadarMacUITests

**Skills to read**: none

Replace the boilerplate test files with a proper interactive control test.

**Tasks:**
- Update `PRRadarMacUITests/PRRadarMacUITests.swift`:
  ```swift
  import XCTest
  import XCUITestControl

  final class InteractiveControlTests: XCTestCase {
      @MainActor
      func testInteractiveControl() throws {
          let app = XCUIApplication()
          app.launch()
          InteractiveControlLoop().run(app: app)
      }
  }
  ```
- Keep `PRRadarMacUITestsLaunchTests.swift` as-is (useful for basic launch screenshot verification)
- Verify the project builds: `xcodebuild build-for-testing -project PRRadar.xcodeproj -scheme PRRadarMac -destination 'platform=macOS'`

**Notes:**
- The test class is named `InteractiveControlTests` to match the convention used in the iOS app and the skill documentation
- The test method `testInteractiveControl` is the entry point that the skill's `xcodebuild` command references

**Completed**: Replaced boilerplate `PRRadarMacUITests.swift` with `InteractiveControlTests` importing `XCUITestControl`. Build initially failed because `XCUIElement.pinch(withScale:velocity:)` is iOS-only — fixed in `xcode-sim-automation` by guarding the call with `#if os(iOS)` (committed as `b1ed645`). `xcodebuild build-for-testing` now succeeds. `PRRadarMacUITestsLaunchTests.swift` kept as-is.

## - [x] Phase 3: Create the Interactive XCUITest Skill

**Skills to read**: none

Create `.claude/skills/interactive-xcuitest/SKILL.md` adapted for macOS PRRadar. This is the primary skill — it enables Claude to dynamically control the app.

**Tasks:**
- Copy the skill from `/Users/bill/Developer/personal/xcode-sim-automation/.claude/skills/interactive-xcuitest/SKILL.md` as the starting template
- Adapt for PRRadar macOS specifics:
  - **xcodebuild command**: Use `-project PRRadar.xcodeproj -scheme PRRadarMac -destination 'platform=macOS'` instead of iOS simulator destination
  - **Test target path**: `-only-testing:"PRRadarMacUITests/InteractiveControlTests/testInteractiveControl"`
  - **Python CLI path**: `../xcode-sim-automation/Tools/xcuitest-control.py` (relative to PRRadar repo root, since the package is local) — or use absolute path `/Users/bill/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py`
  - **Prerequisites section**: Remove SPM install instructions (already configured in the Xcode project). Keep the Python CLI reference.
  - **macOS-specific notes**: No simulator needed, the app runs natively. Mention that the app window must be visible (not minimized).

**Keep from template:**
- Full CLI command reference (tap, scroll, type, adjust, pinch, wait, screenshot, status, done)
- File-based protocol documentation
- Error handling and recovery section
- Multiple match handling documentation
- Keyboard handling notes
- Tips for effective control

**Key differences from iOS skill:**
- macOS destination instead of iOS simulator
- No `run-ui-tests.sh` — just `xcodebuild test` directly
- App window focus may differ (macOS windows can be behind other windows)

**Completed**: Created `.claude/skills/interactive-xcuitest/SKILL.md` adapted from the `xcode-sim-automation` template. Key adaptations: all `xcodebuild` commands use `-project PRRadar.xcodeproj -scheme PRRadarMac -destination 'platform=macOS'`; prerequisites simplified (no SPM setup needed — already configured in the Xcode project); Python CLI referenced at absolute path `/Users/bill/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py`; removed `pinch` from macOS (iOS-only); added macOS-specific notes section covering window visibility, no simulator needed, and build-before-test pattern; added clean-stale-files step to workflow; added skill reference to `CLAUDE.md`. Build verified with `xcodebuild build-for-testing`.

## - [x] Phase 4: Create the Automated Screenshots Skill

**Skills to read**: none

Create `.claude/skills/creating-automated-screenshots/SKILL.md` for pre-scripted screenshot tests.

**Tasks:**
- Copy from `/Users/bill/Developer/personal/xcode-sim-automation/.claude/skills/creating-automated-screenshots/SKILL.md`
- Adapt for PRRadar macOS:
  - Use `PRRadar.xcodeproj` / `PRRadarMac` scheme
  - Use macOS destination
  - Update test target references to `PRRadarMacUITests`
  - Add PRRadar-specific navigation patterns (e.g., sidebar → PR list → detail view)
- Keep: `captureHierarchy`/`findTappable` helpers, element type discovery docs, iterative debugging workflow

**Completed**: Created `.claude/skills/creating-automated-screenshots/SKILL.md` adapted from the `xcode-sim-automation` template. Key adaptations: all `xcodebuild` commands use `-project PRRadar.xcodeproj -scheme PRRadarMac -destination 'platform=macOS'`; prerequisites simplified (no SPM setup needed — already configured in the Xcode project); added PRRadar-specific navigation patterns section documenting the three-column `NavigationSplitView` layout (Config Sidebar → PR List → Detail View) with navigation steps for common views (Summary, Diff, Report, Settings); retained `captureHierarchy`/`findTappable` helpers, element type discovery docs, iterative debugging workflow, and build-first pattern; added macOS-specific notes (no simulator, window visibility, no pinch). Build verified with `xcodebuild build-for-testing`.

## - [x] Phase 5: Add Accessibility Identifiers to Key MacApp Views

**Skills to read**: `swift-app-architecture:swift-swiftui`

For reliable XCUITest automation, key UI elements need accessibility identifiers. Without them, Claude has to guess at element labels which is fragile.

**Files to modify:**
- `PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift` — sidebar config list, PR list, toolbar buttons (Settings, Refresh, Analyze, Folder, Safari)
- `PRRadarLibrary/Sources/apps/MacApp/UI/ReviewDetailView.swift` — phase tabs (Summary, Diff, Report), action buttons
- `PRRadarLibrary/Sources/apps/MacApp/UI/PRListRow.swift` — row identifier for each PR
- `PRRadarLibrary/Sources/apps/MacApp/UI/PipelineStatusView.swift` — phase status nodes
- `PRRadarLibrary/Sources/apps/MacApp/UI/SettingsView.swift` — config list items, edit/delete buttons

**Identifier naming convention** (match what the iOS app uses):
- Use descriptive camelCase: `settingsButton`, `refreshButton`, `analyzeButton`
- For list items, include the dynamic identifier: `prRow_\(pr.number)`
- For phase buttons: `phaseButton_summary`, `phaseButton_diff`, `phaseButton_report`
- For config items: `configRow_\(config.name)`

**Approach:** Add `.accessibilityIdentifier("...")` to each key interactive element. Don't over-tag — focus on elements Claude would need to interact with:
- Navigation targets (buttons, tabs, list rows)
- Text fields (search, config editing)
- Action buttons (run phase, analyze, refresh)

**Completed**: Added `.accessibilityIdentifier()` to all key interactive elements across 5 view files. **ContentView** (13 identifiers): toolbar buttons (`settingsButton`, `refreshButton`, `analyzeButton`, `folderButton`, `safariButton`), config sidebar list + rows (`configSidebar`, `configRow_\(name)`), PR list (`prList`), filter bar controls (`daysFilter`, `stateFilter`, `pendingCommentsToggle`, `refreshListButton`, `analyzeAllButton`, `newReviewButton`), new review popover (`prNumberField`, `startReviewButton`). **ReviewDetailView** (4 identifiers): diff toolbar buttons (`fetchDiffButton`, `rulesTasksButton`), AI output and effective diff sheet buttons (`aiOutputButton`, `effectiveDiffButton`). **PRListRow** (1 identifier): `prRow_\(pr.number)`. **PipelineStatusView** (3 identifiers): `phaseButton_summary`, `phaseButton_diff`, `phaseButton_report`. **SettingsView** (6 identifiers): `addConfigButton`, `settingsDoneButton`, config row + action buttons (`configRow_\(name)`, `editConfig_\(name)`, `setDefaultConfig_\(name)`, `deleteConfig_\(name)`). Build verified with `swift build`.

## - [ ] Phase 6: Test xcodebuild Start/Stop Reliability

**Skills to read**: none

Starting and stopping XCUITests from the command line can be flaky. This phase establishes reliable patterns.

**Tasks:**
- Test building the UI test target:
  ```bash
  xcodebuild build-for-testing -project PRRadar.xcodeproj -scheme PRRadarMac -destination 'platform=macOS'
  ```
- Test running the interactive control test in the background:
  ```bash
  xcodebuild test -project PRRadar.xcodeproj -scheme PRRadarMac -destination 'platform=macOS' \
    -only-testing:"PRRadarMacUITests/InteractiveControlTests/testInteractiveControl" &
  ```
- Verify the wait-for-initialization pattern works:
  ```bash
  while [ ! -f /tmp/xcuitest-hierarchy.txt ]; do sleep 1; done
  ```
- Test sending a command via the Python CLI and reading the response
- Test the `done` command for clean shutdown
- Test that killing the `xcodebuild` process also terminates the test cleanly

**Known issues from the iOS implementation:**
- `xcodebuild test` can hang if the test target fails to build — always `build-for-testing` first as a separate step
- The background `&` process may leave orphaned processes — may need `kill %1` or `pkill -f xcodebuild`
- Stale `/tmp/xcuitest-*.json` files from previous runs can cause confusion — clean them up before starting
- The 5-minute inactivity timeout in `InteractiveControlLoop` will kill the test if Claude takes too long between commands

**Document findings** in the skill's troubleshooting section.

## - [ ] Phase 7: Validation

**Skills to read**: `swift-testing`

End-to-end validation that the full interactive control loop works.

**Validation steps:**
1. Clean stale files: `rm -f /tmp/xcuitest-command.json /tmp/xcuitest-hierarchy.txt /tmp/xcuitest-screenshot.png`
2. Build: `xcodebuild build-for-testing -project PRRadar.xcodeproj -scheme PRRadarMac -destination 'platform=macOS'`
3. Run test in background: `xcodebuild test ... &`
4. Wait for initialization: poll for `/tmp/xcuitest-hierarchy.txt`
5. Read hierarchy to see the initial app state
6. Read screenshot to visually confirm the app launched
7. Execute a tap command via Python CLI (e.g., tap a toolbar button)
8. Verify hierarchy/screenshot updated
9. Send `done` command
10. Verify `xcodebuild` process exits cleanly

**Success criteria:**
- UI test target builds without errors
- Interactive control test starts and the app launches
- Python CLI successfully sends commands and receives responses
- Hierarchy and screenshot files are written and readable
- The `done` command exits the test cleanly
- Skills are well-documented and usable by Claude in future sessions

**Unit tests:** Not applicable — XCUITests require a running app and can't be tested via `swift test`. Validation is manual/interactive.
