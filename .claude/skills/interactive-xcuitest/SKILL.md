---
name: interactive-xcuitest
description: Interactively controls PRRadar MacApp through XCUITest via a Python CLI. Claude reads UI state and screenshots, decides actions, and executes commands. Use for dynamic UI exploration, complex navigation flows, or when pre-scripted navigation isn't feasible.
user-invocable: true
---

# Interactive XCUITest Control

Enables Claude to dynamically control the PRRadar MacApp through XCUITest using a Python CLI that abstracts the file-based protocol. Unlike pre-scripted tests, this allows Claude to explore the UI, make decisions based on current state, and recover from unexpected situations.

## Usage

Invoke this skill when you need to:
- Navigate complex UI flows without knowing the exact path ahead of time
- Explore the MacApp's UI to understand its structure
- Perform multi-step interactions that depend on dynamic content
- Test error recovery and edge cases interactively
- Take screenshots of specific views found through exploration

The skill will ask for your goal if not specified (e.g., "Navigate to Settings and verify config list").

## Prerequisites

The PRRadar Xcode project (`PRRadar.xcodeproj`) already has the `XCUITestControl` package configured as a local SPM dependency and the `PRRadarMacUITests` target linked to it. No additional package setup is needed.

### Python CLI and XCUITestControl Package

The CLI tool and its Swift package are at:

```
~/Developer/personal/xcode-sim-automation/
├── Tools/xcuitest-control.py          # Python CLI (no dependencies)
├── Sources/XCUITestControl/           # Swift XCUITest library
└── Package.swift                      # SPM package
```

The `xcode-sim-automation` package is a **shared, reusable package** — not PRRadar-specific. When this skill is invoked and improvements are identified (new commands, bug fixes, better error handling), **edit the package directly and commit the changes**. This ensures each automation session continually improves the tooling for all projects.

## macOS Sandbox and File Paths

**IMPORTANT**: On macOS, Xcode always sandboxes the XCUITest runner. The test runner **cannot** write to `/tmp/`. Files are written to the runner's sandbox container instead.

The test is configured to write files to:
```
~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp/
```

Use the `--container` (`-c`) flag on every CLI command to set all file paths from this directory:

```bash
CLI=~/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py
CT="$HOME/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp"

python3 $CLI -c "$CT" screenshot
python3 $CLI -c "$CT" tap --target myButton --target-type button
python3 $CLI -c "$CT" scroll --direction down --target prList --target-type any
```

**IMPORTANT**: Shell state does not persist between Bash tool calls. You must include `CLI=...` and `CT=...` in **every** Bash command that uses the Python CLI. The `--container` flag eliminates the need for separate `XCUITEST_*_PATH` env var exports.

## Python CLI

The `xcuitest-control.py` script provides a simple interface for controlling XCUITest. Always use `--container` (`-c`) to set the sandbox paths:

```bash
CLI=~/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py
CT="$HOME/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp"

# Bring app to foreground (ALWAYS do this first!)
python3 $CLI -c "$CT" activate

# Tap a button
python3 $CLI -c "$CT" tap --target submitButton --target-type button

# Scroll down
python3 $CLI -c "$CT" scroll --direction down --target prList --target-type any

# Type text
python3 $CLI -c "$CT" type --value "Hello World"

# Adjust a slider to 75%
python3 $CLI -c "$CT" adjust --target volumeSlider --value 0.75

# Wait 2 seconds
python3 $CLI -c "$CT" wait --value 2.0

# Take screenshot
python3 $CLI -c "$CT" screenshot

# Check status
python3 $CLI -c "$CT" status

# Clean protocol files for fresh session
python3 $CLI -c "$CT" reset

# Check if test is running and ready (with optional wait)
python3 $CLI -c "$CT" ready --timeout 30

# Exit the test
python3 $CLI -c "$CT" done
```

### CLI Output

Each command returns JSON with paths to the latest hierarchy and screenshot:

```json
{
  "status": "completed",
  "hierarchy": "~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp/xcuitest-hierarchy.txt",
  "screenshot": "~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp/xcuitest-screenshot.png"
}
```

On error:
```json
{
  "status": "error",
  "error": "Element 'missingButton' not found after waiting 10 seconds",
  "hierarchy": "~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp/xcuitest-hierarchy.txt",
  "screenshot": "~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp/xcuitest-screenshot.png"
}
```

## Workflow

### 1. Set Up Variables

Set these two variables at the top of every Bash command:

```bash
CLI=~/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py
CT="$HOME/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp"
```

### 2. Kill Stale Processes and Clean Files

Kill any PRRadarMac processes from previous runs (stale processes cause "Failed to terminate" errors):

```bash
pkill -f "PRRadarMac" 2>/dev/null; sleep 2
python3 $CLI -c "$CT" reset
```

### 3. Build and Start the XCUITest

Always build first (catches errors without hanging), then run:

```bash
xcodebuild build-for-testing \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS'
```

**CRITICAL**: The `xcodebuild test-without-building` command **must** be run using the Bash tool's `run_in_background: true` parameter. Do NOT use shell `&` backgrounding — the process will be killed when the Bash tool call completes.

```bash
# Use run_in_background: true on the Bash tool for this command
xcodebuild test-without-building \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS' \
  -only-testing:"PRRadarMacUITests/InteractiveControlTests/testInteractiveControl"
```

The test will:
- Launch the PRRadar MacApp
- Write initial hierarchy and screenshot to the sandbox container
- Begin polling for commands

**macOS note**: No simulator is needed — the app runs natively on the Mac. The app window must be visible (not minimized) for screenshots and element interactions to work correctly.

### 4. Wait for Test Initialization

Use the `ready` command to poll until the test is running (~5 seconds):

```bash
python3 $CLI -c "$CT" ready --timeout 30
```

### 5. Activate the App

**CRITICAL**: Always activate the app first to bring it to the foreground. If the app window is behind other windows, scroll/tap commands will fail with "Unable to find hit point".

```bash
python3 $CLI -c "$CT" activate
```

### 6. Execute Commands

Use the CLI to execute actions:

```bash
# Read current UI state (use the Read tool)
# Read $CT/xcuitest-hierarchy.txt

# View screenshot (use the Read tool)
# Read $CT/xcuitest-screenshot.png

# Execute action
python3 $CLI -c "$CT" tap --target settingsButton --target-type button

# Read updated hierarchy and screenshot after action
```

### 7. Exit Gracefully

When the goal is achieved:

```bash
python3 $CLI -c "$CT" done
```

**Note**: The `done` command will report a timeout from the Python CLI — this is expected. The test exits before writing a "completed" status. Check the xcodebuild output for "TEST EXECUTE SUCCEEDED" to confirm clean shutdown.

After exit, kill any orphaned app processes:

```bash
pkill -f "PRRadarMac" 2>/dev/null
```

## CLI Commands Reference

### tap
Taps an element by identifier.

```bash
python3 $CLI tap --target submitButton --target-type button
python3 $CLI tap -t submitButton -T button
python3 $CLI tap --target Edit --target-type button --index 0
```

Options:
- `--target, -t` (required): Accessibility identifier of the element
- `--target-type, -T` (optional): Element type - `button`, `staticText`, `cell`, `textField`, `slider`, or `any`
- `--index, -i` (optional): 0-based index when multiple elements match. If omitted, taps the first hittable element.

### scroll
Scrolls content in a direction (reveals content in that direction).

**Important**: The direction specifies where you want to scroll TO (what content to reveal), not the swipe gesture direction:
- `--direction down` = reveal content below (internally swipes up)
- `--direction up` = reveal content above (internally swipes down)
- `--direction left` = reveal content to the left (internally swipes right)
- `--direction right` = reveal content to the right (internally swipes left)

```bash
python3 $CLI scroll --direction down   # Scroll down to see more content below
python3 $CLI scroll -d up --target scrollView  # Scroll up to see content above
```

Options:
- `--direction, -d` (required): `up`, `down`, `left`, or `right` - the direction to scroll content
- `--target, -t` (optional): Element to scroll. If omitted, scrolls the app.

### type
Types text into a text field.

```bash
python3 $CLI type --value "test@example.com"
python3 $CLI type -V "Hello" --target usernameField
```

Options:
- `--value, -V` (required): Text to type
- `--target, -t` (optional): Text field to type into. If omitted, types into currently focused field.

### adjust
Adjusts a slider to a normalized position (0.0 to 1.0).

```bash
python3 $CLI adjust --target volumeSlider --value 0.75
python3 $CLI adjust -t volumeSlider -V 0.5
```

Options:
- `--target, -t` (required): Accessibility identifier of the slider
- `--value, -V` (required): Normalized position between 0.0 (minimum) and 1.0 (maximum)

### wait
Pauses for a specified duration.

```bash
python3 $CLI wait --value 2.0
python3 $CLI wait  # defaults to 1.0 second
```

Options:
- `--value, -V` (optional): Seconds to wait. Defaults to 1.0.

### screenshot
Captures current state without performing any action.

```bash
python3 $CLI screenshot
```

### status
Checks current command status without executing.

```bash
python3 $CLI status
```

### activate
Brings the app to the foreground. **Always call this after starting the test** — if the app window is behind other windows, scroll/tap actions will fail with "Unable to find hit point".

```bash
python3 $CLI -c "$CT" activate
```

### reset
Cleans protocol files for a fresh session. Use before starting a new test.

```bash
python3 $CLI -c "$CT" reset
```

### ready
Checks if XCUITest is running and ready for commands. With `--timeout`, polls until ready or timeout expires.

```bash
python3 $CLI -c "$CT" ready                  # Instant check
python3 $CLI -c "$CT" ready --timeout 30     # Wait up to 30 seconds
```

Options:
- `--timeout, -t` (optional): Seconds to wait for ready state. Defaults to 0 (instant check).

### done
Exits the test loop.

```bash
python3 $CLI -c "$CT" done
```

## Handling Multiple Matches

When multiple elements share the same identifier (e.g., multiple "Edit" buttons in a list), the tap command:

1. **Without `--index`**: Automatically finds and taps the first hittable element
2. **With `--index N`**: Taps the element at the specified 0-based index

### Success Response with Multiple Matches

When a tap succeeds on one of multiple matches, the response includes info:

```json
{
  "status": "completed",
  "info": "Tapped button at index 0 of 5 matches",
  "hierarchy": "...",
  "screenshot": "..."
}
```

### Error Response for Ambiguous Elements

When multiple elements match but none are hittable:

```json
{
  "status": "error",
  "error": "Found 5 elements matching 'Edit', none were hittable. Specify --index 0 to 4 to select a specific element.",
  "hierarchy": "...",
  "screenshot": "..."
}
```

### Index Out of Range

When the specified index exceeds available matches:

```json
{
  "status": "error",
  "error": "Index 10 out of range. Found 5 'Edit' element(s). Use --index 0 to 4.",
  "hierarchy": "...",
  "screenshot": "..."
}
```

### Best Practices

1. **Check the hierarchy first** to see how many matching elements exist
2. **Use `--index` when you know which element** you want (e.g., the second Edit button)
3. **Let the framework auto-select** when you want any visible/hittable match
4. **Review the `info` field** to verify which element was tapped

## Keyboard Handling

When interacting with text fields, the keyboard may appear and affect other UI elements.

### Dismissing the Keyboard

Tap on a non-interactive element that's visible:

```bash
python3 $CLI tap --target notesLabel --target-type staticText
```

**Tips for dismissing the keyboard:**
- Look in the hierarchy for `StaticText` elements (labels) that are above the keyboard
- Navigation bar titles work well as tap targets
- Section headers or form labels are good choices
- On macOS, pressing Escape can also dismiss keyboards/popovers — use `type --value "\u{1b}"` if needed

### Typing Text

1. **Tap the text field first** to focus it:
   ```bash
   python3 $CLI tap --target searchBar --target-type any
   ```

2. **Then type your text**:
   ```bash
   python3 $CLI type --value "Hello"
   ```

### Common Keyboard Issues

| Issue | Solution |
|-------|----------|
| Keyboard blocking elements | Tap a non-interactive label to dismiss |
| Element not hittable | The element may be behind the keyboard — dismiss keyboard first |
| Can't scroll | Keyboard may be intercepting gestures — dismiss it first |
| Text not appearing | Ensure the text field was tapped/focused before typing |

## Reading the UI Hierarchy

The hierarchy file shows the element tree with types, identifiers, and labels:

```
Application, pid: 12345, label: 'PRRadar'
  Window, 0x600000001234
    Other, identifier: 'mainView'
      Button, identifier: 'settingsButton', label: 'Settings'
      StaticText, identifier: 'welcomeLabel', label: 'Welcome!'
      Cell, identifier: 'configRow_test-repo', label: 'test-repo'
```

From this hierarchy:
- `settingsButton` is a **Button** → `--target-type button`
- `welcomeLabel` is a **StaticText** → `--target-type staticText`
- `configRow_test-repo` is a **Cell** → `--target-type cell`

Use `--target-type any` if unsure — it searches all element types.

## Error Handling and Recovery

### Robustness Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| Maximum actions | 100 | Prevents infinite loops |
| Command timeout | 5 minutes | XCUITest exits if no commands received |
| Element timeout | 10 seconds | Actions fail gracefully if element not found |
| Tap retry count | 3 | Retries if element exists but not hittable |

### Command Errors

On error, the CLI returns:
```json
{
  "status": "error",
  "error": "Element 'missingButton' not found after waiting 10 seconds",
  "hierarchy": "...",
  "screenshot": "..."
}
```

When this happens:
1. Read the hierarchy to find the correct element
2. Try alternative identifiers or element types
3. Consider if navigation went to an unexpected view
4. Check if the element needs to be scrolled into view

### Common Errors

| Error | Solution |
|-------|----------|
| Element not found | Check hierarchy for correct identifier, try `--target-type any` |
| Element not hittable | Wait for animations, scroll element into view, retry |
| Multiple matches, none hittable | Use `--index` to select specific element, or scroll to reveal hittable ones |
| Index out of range | Check hierarchy to count matches, use valid index (0 to N-1) |
| Wrong element type | Use `--target-type any` or check hierarchy for actual type |
| Action limit reached | Break goal into smaller steps, restart skill |
| Test timeout | XCUITest exited due to 5 min inactivity, restart test |

## macOS-Specific Notes

- **No simulator needed**: The app runs natively on macOS. Use `-destination 'platform=macOS'`.
- **Sandbox**: Xcode always sandboxes the XCUITest runner on macOS. Files must be written to the sandbox container, not `/tmp/`. See "macOS Sandbox and File Paths" section above.
- **Window visibility**: The app window must be visible (not minimized or fully occluded) for screenshots and interactions to work.
- **Window focus**: macOS windows can be behind other windows. If interactions fail, run `activate` to bring the app to foreground. Always do this after starting the test.
- **Pinch not available**: The `pinch` command is iOS-only and will not work on macOS.
- **Build first**: Always run `xcodebuild build-for-testing` before `xcodebuild test` to catch build errors early — `xcodebuild test` can hang if the build fails.
- **Kill stale processes**: Always kill any running PRRadarMac before starting a test. Stale app processes cause "Failed to terminate" errors.
- **Orphaned processes**: Killing `xcodebuild` terminates the test runner but leaves the PRRadarMac app running. Always `pkill -f "PRRadarMac"` after stopping.
- **Automation mode timeout**: The first run after an Xcode restart may fail with "Timed out while enabling automation mode." Retry usually succeeds.
- **"Automation Running" notification**: macOS shows a system notification/banner when XCUITest starts automating a native app. This is normal macOS behavior — it doesn't happen on iOS because iOS tests run inside the Simulator. The notification is harmless and does not indicate a different automation mechanism is being used. The implementation uses standard XCUITest APIs (same as the iOS project).

## Example Session

**Goal**: Explore the PRRadar MacApp UI

```bash
CLI=~/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py
CT="$HOME/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp"

# 1. Kill stale processes and clean files
pkill -f "PRRadarMac" 2>/dev/null; sleep 2
python3 $CLI -c "$CT" reset

# 2. Build first (catches build errors without hanging)
xcodebuild build-for-testing \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS'

# 3. Start the test (MUST use Bash tool's run_in_background: true)
xcodebuild test-without-building \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS' \
  -only-testing:"PRRadarMacUITests/InteractiveControlTests/testInteractiveControl"

# 4. Wait for initialization
python3 $CLI -c "$CT" ready --timeout 30

# 5. Bring app to foreground
python3 $CLI -c "$CT" activate

# 6. Read initial state
# Use the Read tool on $CT/xcuitest-screenshot.png
# Use Grep on $CT/xcuitest-hierarchy.txt to search for elements

# 7. Tap an element based on what you see
python3 $CLI -c "$CT" tap --target settingsButton --target-type button

# 8. Read updated hierarchy and screenshot
# Use the Read tool on $CT/xcuitest-hierarchy.txt

# 9. Exit when done
python3 $CLI -c "$CT" done

# 10. Clean up orphaned app process
pkill -f "PRRadarMac" 2>/dev/null
```

## File-Based Protocol (Advanced)

For direct JSON manipulation, the CLI uses these files:

| File | Purpose |
|------|---------|
| `$CONTAINER_TMP/xcuitest-command.json` | Commands from Claude → XCUITest |
| `$CONTAINER_TMP/xcuitest-hierarchy.txt` | UI hierarchy from XCUITest → Claude |
| `$CONTAINER_TMP/xcuitest-screenshot.png` | Screenshot from XCUITest → Claude |

Where `CONTAINER_TMP=~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp`.

### Command JSON Schema

```json
{
  "action": "tap" | "scroll" | "type" | "wait" | "screenshot" | "adjust" | "activate" | "done",
  "target": "elementIdentifier",
  "targetType": "button" | "staticText" | "cell" | "textField" | "slider" | "any",
  "index": 0,
  "value": "text to type (for type) or 0.0-1.0 (for adjust)",
  "direction": "up" | "down" | "left" | "right",
  "status": "pending" | "executing" | "completed" | "error",
  "errorMessage": "optional error description",
  "info": "optional diagnostic info (e.g., which index was tapped)"
}
```

## Troubleshooting

### Files not appearing / hierarchy not written

The XCUITest runner is sandboxed on macOS and **cannot write to `/tmp/`**. Ensure:
1. The test uses `InteractiveControlLoop.Configuration` with container paths (already configured in `PRRadarMacUITests.swift`)
2. The Python CLI has `XCUITEST_*_PATH` environment variables set to the container paths
3. Check the container directory: `ls ~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp/`

### "Failed to terminate org.gestrich.PRRadar"

A PRRadarMac process from a previous run is still active. Fix:
```bash
pkill -f "PRRadarMac" 2>/dev/null; sleep 2
```

### "Timed out while enabling automation mode"

This can happen on the first run after an Xcode restart, or when running from a non-GUI terminal. Fix:
- Retry the test — second attempt usually succeeds
- Ensure Xcode is running and the terminal has Accessibility permissions (System Settings > Privacy & Security > Accessibility)

### `done` command reports timeout

This is **expected behavior**. The test exits immediately on `done` without writing a "completed" status back. The Python CLI times out waiting for a response that never comes. The test itself exits cleanly — check the xcodebuild output for "TEST EXECUTE SUCCEEDED".

### "Unable to find hit point for Application"

The app window is behind other windows and isn't hittable. Fix:
```bash
python3 $CLI -c "$CT" activate
```
This brings the app to the foreground. **Always run `activate` after starting the test** before any scroll/tap commands.

### Orphaned PRRadarMac process after test exit

Killing `xcodebuild` or sending `done` terminates the test runner but leaves the app running. Always clean up:
```bash
pkill -f "PRRadarMac" 2>/dev/null
```

### Test hangs at "Find the Target Application"

This typically means `app.debugDescription` is taking a long time (the UI hierarchy can be 200KB+). Wait longer — it should complete within 5-10 seconds. If it persists, kill and restart.

## Tips for Effective Control

1. **Always activate first** — Run `activate` after starting the test to bring the app to foreground. Skipping this causes "Unable to find hit point" errors.
2. **Always read hierarchy first** — Don't guess element identifiers
3. **Use `--container` (`-c`) flag** — Set all file paths with one flag. Eliminates env var exports.
4. **Use specific target-type** — Faster and more reliable than `any`
5. **Handle errors gracefully** — Read hierarchy after errors to adapt
6. **Wait after animations** — Use the `wait` command if UI is animating
7. **Take screenshots often** — Helps verify you're on the expected view
8. **Exit cleanly** — Always run `done` command when finished
9. **Track action count** — Monitor progress against the 100 action limit
10. **Handle keyboard** — Dismiss by tapping non-interactive labels
11. **Retry with alternatives** — Use `--target-type any` if specific type fails
12. **Build before test** — Always `build-for-testing` first to avoid hangs
13. **Hierarchy is large (1500+ lines)** — Use Grep to search for specific identifiers or text values rather than reading the entire file linearly. Read the screenshot first to know what to search for.
14. **Re-set CLI/CT vars every command** — Shell state doesn't persist between Bash tool calls. Every CLI invocation needs `CLI=...` and `CT=...`.
15. **Scroll with a target** — When scrolling lists, use `--target <listIdentifier> --target-type any` rather than scrolling the app itself, which can fail if the app window isn't fully hittable.
16. **Improve the shared package** — When you discover issues or missing features in `xcode-sim-automation`, edit the package directly and commit. See the package section above.
