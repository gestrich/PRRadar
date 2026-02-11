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

### Python CLI

The CLI tool is located at:

```
/Users/bill/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py
```

No additional Python dependencies are required — the script uses only the standard library.

## Python CLI

The `xcuitest-control.py` script provides a simple interface for controlling XCUITest:

```bash
CLI=/Users/bill/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py

# Tap a button
python3 $CLI tap --target submitButton --target-type button

# Scroll down
python3 $CLI scroll --direction down

# Type text
python3 $CLI type --value "Hello World"

# Adjust a slider to 75%
python3 $CLI adjust --target volumeSlider --value 0.75

# Wait 2 seconds
python3 $CLI wait --value 2.0

# Take screenshot
python3 $CLI screenshot

# Check status
python3 $CLI status

# Exit the test
python3 $CLI done
```

### CLI Output

Each command returns JSON with paths to the latest hierarchy and screenshot:

```json
{
  "status": "completed",
  "hierarchy": "/tmp/xcuitest-hierarchy.txt",
  "screenshot": "/tmp/xcuitest-screenshot.png"
}
```

On error:
```json
{
  "status": "error",
  "error": "Element 'missingButton' not found after waiting 10 seconds",
  "hierarchy": "/tmp/xcuitest-hierarchy.txt",
  "screenshot": "/tmp/xcuitest-screenshot.png"
}
```

## Workflow

### 1. Start the XCUITest

First, clean stale files from any previous run:

```bash
rm -f /tmp/xcuitest-command.json /tmp/xcuitest-hierarchy.txt /tmp/xcuitest-screenshot.png
```

Then build and run the interactive control test:

```bash
xcodebuild test \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS' \
  -only-testing:"PRRadarMacUITests/InteractiveControlTests/testInteractiveControl" &
```

The test will:
- Launch the PRRadar MacApp
- Write initial hierarchy and screenshot
- Begin polling for commands

**macOS note**: No simulator is needed — the app runs natively on the Mac. The app window must be visible (not minimized) for screenshots and element interactions to work correctly.

### 2. Wait for Test Initialization

Poll until the hierarchy file exists:

```bash
while [ ! -f /tmp/xcuitest-hierarchy.txt ]; do sleep 1; done
```

Or use the status command:
```bash
python3 /Users/bill/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py status
```

### 3. Execute Commands

Use the CLI to execute actions:

```bash
CLI=/Users/bill/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py

# Read current UI state
cat /tmp/xcuitest-hierarchy.txt

# View screenshot
# Use the Read tool on /tmp/xcuitest-screenshot.png

# Execute action
python3 $CLI tap --target settingsButton --target-type button

# View updated hierarchy and screenshot after action
cat /tmp/xcuitest-hierarchy.txt
```

### 4. Exit Gracefully

When the goal is achieved:

```bash
python3 /Users/bill/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py done
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

### done
Exits the test loop.

```bash
python3 $CLI done
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
  "hierarchy": "/tmp/xcuitest-hierarchy.txt",
  "screenshot": "/tmp/xcuitest-screenshot.png"
}
```

### Error Response for Ambiguous Elements

When multiple elements match but none are hittable:

```json
{
  "status": "error",
  "error": "Found 5 elements matching 'Edit', none were hittable. Specify --index 0 to 4 to select a specific element.",
  "hierarchy": "/tmp/xcuitest-hierarchy.txt",
  "screenshot": "/tmp/xcuitest-screenshot.png"
}
```

### Index Out of Range

When the specified index exceeds available matches:

```json
{
  "status": "error",
  "error": "Index 10 out of range. Found 5 'Edit' element(s). Use --index 0 to 4.",
  "hierarchy": "/tmp/xcuitest-hierarchy.txt",
  "screenshot": "/tmp/xcuitest-screenshot.png"
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
  "hierarchy": "/tmp/xcuitest-hierarchy.txt",
  "screenshot": "/tmp/xcuitest-screenshot.png"
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
- **Window visibility**: The app window must be visible (not minimized or fully occluded) for screenshots and interactions to work.
- **Window focus**: macOS windows can be behind other windows. If interactions fail, ensure the PRRadar window is frontmost.
- **Pinch not available**: The `pinch` command is iOS-only and will not work on macOS.
- **Build first**: Always run `xcodebuild build-for-testing` before `xcodebuild test` to catch build errors early — `xcodebuild test` can hang if the build fails.

## Example Session

**Goal**: Explore the PRRadar MacApp UI

```bash
CLI=/Users/bill/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py

# 1. Clean stale files
rm -f /tmp/xcuitest-command.json /tmp/xcuitest-hierarchy.txt /tmp/xcuitest-screenshot.png

# 2. Build first (catches build errors without hanging)
xcodebuild build-for-testing \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS'

# 3. Start the test
xcodebuild test \
  -project PRRadar.xcodeproj \
  -scheme PRRadarMac \
  -destination 'platform=macOS' \
  -only-testing:"PRRadarMacUITests/InteractiveControlTests/testInteractiveControl" &

# 4. Wait for initialization
while [ ! -f /tmp/xcuitest-hierarchy.txt ]; do sleep 1; done

# 5. Read initial state
cat /tmp/xcuitest-hierarchy.txt

# 6. Read the screenshot to see the current view
# Use the Read tool on /tmp/xcuitest-screenshot.png

# 7. Tap an element based on what you see
python3 $CLI tap --target settingsButton --target-type button

# 8. Read updated hierarchy and screenshot
cat /tmp/xcuitest-hierarchy.txt

# 9. Exit when done
python3 $CLI done
```

## Environment Variable Overrides

The CLI supports environment variable overrides for file paths:

| Variable | Default | Description |
|----------|---------|-------------|
| `XCUITEST_COMMAND_PATH` | `/tmp/xcuitest-command.json` | Path to command JSON file |
| `XCUITEST_HIERARCHY_PATH` | `/tmp/xcuitest-hierarchy.txt` | Path to hierarchy output |
| `XCUITEST_SCREENSHOT_PATH` | `/tmp/xcuitest-screenshot.png` | Path to screenshot output |

When using custom paths, also configure the Swift `InteractiveControlLoop.Configuration` to match:

```swift
let config = InteractiveControlLoop.Configuration(
    commandPath: "/custom/path/command.json",
    hierarchyPath: "/custom/path/hierarchy.txt",
    screenshotPath: "/custom/path/screenshot.png"
)
InteractiveControlLoop(configuration: config).run(app: app)
```

## File-Based Protocol (Advanced)

For direct JSON manipulation, the CLI uses these files:

| File | Purpose |
|------|---------|
| `/tmp/xcuitest-command.json` | Commands from Claude → XCUITest |
| `/tmp/xcuitest-hierarchy.txt` | UI hierarchy from XCUITest → Claude |
| `/tmp/xcuitest-screenshot.png` | Screenshot from XCUITest → Claude |

### Command JSON Schema

```json
{
  "action": "tap" | "scroll" | "type" | "wait" | "screenshot" | "adjust" | "done",
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

## Tips for Effective Control

1. **Always read hierarchy first** — Don't guess element identifiers
2. **Use specific target-type** — Faster and more reliable than `any`
3. **Handle errors gracefully** — Read hierarchy after errors to adapt
4. **Wait after animations** — Use the `wait` command if UI is animating
5. **Take screenshots often** — Helps verify you're on the expected view
6. **Exit cleanly** — Always run `done` command when finished
7. **Track action count** — Monitor progress against the 100 action limit
8. **Handle keyboard** — Dismiss by tapping non-interactive labels
9. **Retry with alternatives** — Use `--target-type any` if specific type fails
10. **Build before test** — Always `build-for-testing` first to avoid hangs
