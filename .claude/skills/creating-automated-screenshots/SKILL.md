---
name: creating-automated-screenshots
description: Creates automated UI test for a view, runs it, and captures screenshots to ~/Downloads. Use when the user asks to create screenshots, capture UI images, test view rendering, or generate visual documentation for a PRRadar MacApp view.
user-invocable: true
---

# Automated Screenshot Creator

Creates a UI automation test for a specific PRRadar MacApp view, executes the test, and extracts screenshots. This skill automates the entire workflow from test creation to screenshot extraction.

## Usage

Invoke this skill when you need to:
- Generate screenshots of a specific view for documentation or review
- Create automated visual tests for a new or modified view
- Capture the current state of a UI component

The skill will ask you which view to screenshot if you don't specify one.

## Prerequisites

The PRRadar Xcode project (`PRRadar.xcodeproj`) already has the `XCUITestControl` package configured as a local SPM dependency and the `PRRadarMacUITests` target linked to it. No additional package setup is needed.

### Python CLI

The CLI tool is located at:

```
/Users/bill/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py
```

No additional Python dependencies are required — the script uses only the standard library.

## Workflow

The skill executes these steps automatically:

### 1. Create UI Test File

Creates a new Swift test file in `PRRadarMacUITests/` that:
- Inherits from `XCTestCase`
- Navigates to the target view
- Takes a screenshot using `XCTAttachment`

**Test file naming**: `ScreenshotTest_<ViewName>.swift`

Example test structure:
```swift
import XCTest

final class ScreenshotTest_PRDetail: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Helpers

    /// Captures UI hierarchy at current state for debugging
    func captureHierarchy(name: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name).txt"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    /// Finds a tappable element by trying Button, StaticText, then Cell
    func findTappable(_ identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: 2.0) { return button }

        let staticText = app.staticTexts[identifier]
        if staticText.waitForExistence(timeout: 2.0) { return staticText }

        let cell = app.cells[identifier]
        if cell.waitForExistence(timeout: 2.0) { return cell }

        return button // Fallback - assertion will fail with clear message
    }

    // MARK: - Test

    func testPRDetailScreenshot() throws {
        // Step 1: Wait for the app to load
        captureHierarchy(name: "Step1-InitialState")
        sleep(2)

        // Step 2: Select a config from the sidebar
        let configRow = findTappable("test-repo")
        XCTAssertTrue(configRow.exists, "Config row should exist")
        configRow.tap()
        sleep(2)
        captureHierarchy(name: "Step2-AfterConfigSelection")

        // Step 3: Select a PR from the list
        let prRow = findTappable("PR #1")
        XCTAssertTrue(prRow.exists, "PR row should exist")
        prRow.tap()
        sleep(2)
        captureHierarchy(name: "Step3-AfterPRSelection")

        // Take screenshot
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "PRDetail"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Final hierarchy capture
        captureHierarchy(name: "Final-PRDetailView")
    }
}
```

**Key patterns:**
- `captureHierarchy(name:)` saves the UI state at each step for debugging
- `findTappable(_:)` tries Button → StaticText → Cell automatically
- Each navigation step captures the hierarchy, so if step 3 fails, you have step 1 and 2 hierarchies to analyze

### 2. Build and Run the Test

Run the specific test using `xcodebuild`:

```bash
xcodebuild test \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS' \
  -only-testing:"PRRadarMacUITests/ScreenshotTest_PRDetail/testPRDetailScreenshot"
```

**macOS note**: No simulator is needed — the app runs natively. Always run `xcodebuild build-for-testing` first to catch build errors early (see Build First pattern below).

### 3. Extract Screenshots and Debug Info

Extract screenshots from the `.xcresult` bundle:

```bash
# Find the latest xcresult
RESULT_BUNDLE=$(ls -td ~/Library/Developer/Xcode/DerivedData/*/Logs/Test/*.xcresult | head -1)

# Extract attachments
xcrun xcresulttool get --path "$RESULT_BUNDLE" --list
```

**Extracted files include**:
- Screenshot images (PNG format)
- Hierarchy text files from `captureHierarchy` calls
- Any other test attachments

## PRRadar-Specific Navigation Patterns

PRRadar uses a three-column `NavigationSplitView` layout:

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

### Navigation Steps for Common Views

**PR Summary view** (default after selecting a PR):
```swift
// 1. Select config → 2. Select PR → Summary is shown by default
```

**Diff view**:
```swift
// 1. Select config → 2. Select PR → 3. Tap "Diff" in pipeline status
```

**Report view**:
```swift
// 1. Select config → 2. Select PR → 3. Tap "Report" in pipeline status
```

**Settings sheet**:
```swift
// Tap the gear toolbar button
let settingsButton = app.buttons["Manage configurations"]
settingsButton.tap()
```

## Element Type Discovery

### CRITICAL: Element Types Don't Match Visual Appearance

XCUITest queries are **type-specific**. This means:
- `app.buttons["FBOs"]` will **NOT** find a StaticText labeled "FBOs"
- `app.staticTexts["Settings"]` will **NOT** find a Button labeled "Settings"

Even though both elements might look identical and be tappable, you **must** use the correct element type in your query.

### Common Misconceptions

| Visual Appearance | Common Assumption | Actual Type (Often) |
|-------------------|-------------------|---------------------|
| Tappable link text | Button | **StaticText** |
| Quick action in a list | Button | **StaticText** inside Other |
| Menu item in table | Button | **Cell** or **StaticText** |
| Segmented control item | Button | **Button** (correct) |
| Tab bar item | Button | **Button** (usually correct) |
| Icon that opens something | Button | **Image** or **Button** |

### Try Multiple Element Types

Instead of guessing, try both common types. Use a short timeout for the first attempt:

```swift
// Try as Button first (short timeout), then StaticText
var element = app.buttons["MyElement"]
if !element.waitForExistence(timeout: 2.0) {
    element = app.staticTexts["MyElement"]
}
XCTAssertTrue(element.waitForExistence(timeout: 5.0), "MyElement should exist (as Button or StaticText)")
element.tap()
```

Or use the `findTappable` helper shown in the test template above.

### Reading the UI Hierarchy

The hierarchy shows element types explicitly:
```
Other, identifier: 'QuickActions'
  ↳ StaticText, label: 'Action1'        ← This is a StaticText, NOT a Button!
  ↳ StaticText, label: 'Action2'
Button, identifier: 'MainButton', label: 'MainButton'  ← This IS a Button
```

From this you can determine:
- "Action1" is a **StaticText** → use `app.staticTexts["Action1"]`
- "MainButton" is a **Button** → use `app.buttons["MainButton"]`

## Navigation Patterns

The test navigation depends on where the view is located in the app.

### CRITICAL: Use Assertions for Every Navigation Step

**Every navigation step MUST use `XCTAssertTrue` to verify the element exists before interacting with it.** This ensures the test fails immediately if navigation goes wrong, rather than silently continuing and taking a screenshot of the wrong view.

### Sidebar Items (Config List)
```swift
let configItem = findTappable("test-repo")
XCTAssertTrue(configItem.exists, "Config 'test-repo' should exist in sidebar")
configItem.tap()
```

### PR List Items
```swift
let prRow = findTappable("PR #1")
XCTAssertTrue(prRow.exists, "PR #1 should exist in list")
prRow.tap()
```

### Pipeline Phase Navigation
```swift
// The pipeline status bar contains tappable phase nodes
let diffPhase = findTappable("Diff")
XCTAssertTrue(diffPhase.exists, "Diff phase should exist")
diffPhase.tap()
```

### Toolbar Buttons
```swift
// Toolbar buttons use their help text as labels
let settingsButton = app.buttons["Manage configurations"]
XCTAssertTrue(settingsButton.waitForExistence(timeout: 5.0), "Settings button should exist")
settingsButton.tap()
```

### SwiftUI Sheets/Modals
```swift
let showButton = app.buttons["AccessibilityID"]
XCTAssertTrue(showButton.waitForExistence(timeout: 10.0), "Show button should exist")
showButton.tap()
sleep(2) // Wait for animation
```

### Multi-Step Navigation
For views that require multiple navigation steps, capture hierarchy at each step and use `findTappable` for uncertain elements:
```swift
// Step 1: Select a config
let config = findTappable("test-repo")
XCTAssertTrue(config.exists, "Config should exist")
config.tap()
sleep(2)
captureHierarchy(name: "Step1-AfterConfig")

// Step 2: Select a PR
let pr = findTappable("PR #1")
XCTAssertTrue(pr.exists, "PR should exist")
pr.tap()
sleep(2)
captureHierarchy(name: "Step2-AfterPR")

// Step 3: Navigate to a phase tab
let report = findTappable("Report")
XCTAssertTrue(report.exists, "Report tab should exist")
report.tap()
sleep(2)
captureHierarchy(name: "Step3-AfterReport")

// Take the screenshot
let screenshot = app.screenshot()
```

With hierarchy captures at each step, if the test fails at Step 3, you can examine `Step2-AfterPR.txt` to see what was actually on screen.

## UI Hierarchy Debugging

When navigation fails, the test automatically captures the UI hierarchy to help debug accessibility IDs and element structure.

### Automatic Capture

The test includes `captureHierarchy` calls that save `app.debugDescription` as attachments. This provides:
- Complete element tree with accessibility identifiers
- Element types (Button, StaticText, Cell, etc.)
- Element values and labels
- Element hierarchy and nesting

### Using Hierarchy for Navigation

Example hierarchy output:
```
Button, identifier: "Manage configurations", label: "Manage configurations"
  ↳ Image, label: "gear"
Table
   ↳ Cell, identifier: "test-repo"
      ↳ StaticText, label: "test-repo"
      ↳ StaticText, label: "PRRadar-TestRepo"
```

From this you can determine:
- The settings button identifier is "Manage configurations"
- The config row is in a Cell with identifier "test-repo"
- The text labels are "test-repo" and "PRRadar-TestRepo"

### Debug at Specific Points

Use the `captureHierarchy` helper at each navigation step:
```swift
captureHierarchy(name: "Step1-AfterConfigSelection")
// ... navigate ...
captureHierarchy(name: "Step2-AfterPRSelection")
// ... navigate ...
captureHierarchy(name: "Step3-AfterPhaseSwitch")
```

This creates multiple hierarchy files in the output, letting you see exactly what was on screen at each point.

### Iterative Debugging Workflow

When navigation code needs fixing:

1. **Run test** → Test fails at some step
2. **Check hierarchy files** → Open the step hierarchy files from the xcresult attachments
3. **Find the issue** → The hierarchy from the step BEFORE failure shows what was actually on screen
4. **Update test** → Fix the navigation code (wrong element type? wrong identifier?)
5. **Re-run test** → Just re-run `xcodebuild test`

## Build First Pattern

Always build before running tests to catch compilation errors early:

```bash
# Step 1: Build (catches errors without hanging)
xcodebuild build-for-testing \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS'

# Step 2: Run the specific test
xcodebuild test \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS' \
  -only-testing:"PRRadarMacUITests/ScreenshotTest_MyFeature/testMyFeatureScreenshot"
```

`xcodebuild test` can hang if the build fails, so always separate the build step.

## macOS-Specific Notes

- **No simulator needed**: The app runs natively on macOS. Use `-destination 'platform=macOS'`.
- **Window visibility**: The app window must be visible (not minimized or fully occluded) for screenshots and interactions to work.
- **Window focus**: macOS windows can be behind other windows. If interactions fail, ensure the PRRadar window is frontmost.
- **Pinch not available**: The `pinch` command is iOS-only and will not work on macOS.

## Example Usage

**User request**: "Create a screenshot test for the Report view"

**Skill will**:
1. Ask for navigation details (if not obvious)
2. Create `ScreenshotTest_Report.swift` in `PRRadarMacUITests/` (includes hierarchy capture)
3. Build: `xcodebuild build-for-testing -project PRRadar.xcodeproj -scheme PRRadarMac -destination 'platform=macOS'`
4. Run the test: `xcodebuild test -project PRRadar.xcodeproj -scheme PRRadarMac -destination 'platform=macOS' -only-testing:"PRRadarMacUITests/ScreenshotTest_Report/testReportScreenshot"`
5. Extract screenshots from the xcresult bundle
6. Report the output location

**If navigation fails**: Check hierarchy attachments to find correct element identifiers, then update the test with proper accessibility IDs.

## Error Handling

Common issues:

- **Test passes but screenshot shows wrong view**: Navigation failed silently because `if` statements were used instead of `XCTAssertTrue`. Always use assertions for every navigation step.
- **Element not found but it's clearly visible**: You're using the wrong element type. `app.buttons["Item"]` won't find a StaticText. Check the UI hierarchy to find the actual element type, or use the `findTappable` helper.
- **Test fails to find view**: Check hierarchy attachments to see available accessibility IDs and element structure.
- **Build hangs during test**: Always run `xcodebuild build-for-testing` as a separate step before `xcodebuild test`.
- **Navigation element not found**: Review the captured UI hierarchy to find the correct element identifier or query.
- **Window not visible**: On macOS, the app window must not be minimized. Ensure it's visible before running tests.
