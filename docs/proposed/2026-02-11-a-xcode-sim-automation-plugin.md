# Convert xcode-sim-automation to a Claude Code Plugin

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `interactive-xcuitest` | Current PRRadar skill for interactive XCUITest control — to be migrated |
| `creating-automated-screenshots` | Current PRRadar skill for screenshot automation — to be migrated |

## Background

The `xcode-sim-automation` package (`~/Developer/personal/xcode-sim-automation`) provides a Swift library (`XCUITestControl`) and Python CLI (`Tools/xcuitest-control.py`) for AI-driven XCUITest automation. Currently, PRRadar has two skills in `.claude/skills/` that are heavily customized with PRRadar-specific details (sandbox paths, Xcode project names, navigation patterns, etc.). The `xcode-sim-automation` repo also has its own generic versions of these skills in `.claude/skills/`.

The goal is to make `xcode-sim-automation` a self-contained Claude Code plugin with reusable skills and scripts. Host apps (like PRRadar) install the plugin and provide a minimal configuration file with their app-specific details. This eliminates skill duplication across projects and centralizes operational learnings in one place.

### Key Insight: Two Layers of Content

Comparing the PRRadar skills (643 and 445 lines) with the generic xcode-sim-automation skills (539 and 364 lines), there's significant overlap but also PRRadar-specific content:

**Generic (belongs in plugin):**
- Python CLI reference (commands, flags, JSON protocol)
- XCUITest setup instructions (add SPM dep, create test class)
- Error handling, recovery, troubleshooting
- Element type discovery, hierarchy reading
- Keyboard handling, multiple match handling
- Build-first pattern, test lifecycle

**App-specific (belongs in host config/override):**
- Xcode project/scheme/destination
- Sandbox container path (`~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp/`)
- UI test target name and test method
- Navigation patterns (PRRadar's three-column NavigationSplitView)
- Accessibility identifiers
- Known app-specific issues (kill stale `PRRadarMac` processes)

### Reference Plugin Structure (swift-app-architecture)

The `swift-app-architecture` repo is the reference implementation. Its plugin structure **must be followed exactly** — plugins are notorious for failing to load due to convention violations.

```
swift-app-architecture/
├── .claude-plugin/
│   └── marketplace.json          ← Root-level marketplace registration
├── plugin/
│   ├── .claude-plugin/
│   │   └── plugin.json           ← Plugin metadata (ONLY file in .claude-plugin/)
│   ├── LICENSE
│   └── skills/
│       ├── swift-architecture/
│       │   ├── SKILL.md          ← Skill entry point with YAML frontmatter
│       │   ├── layers.md         ← Supporting docs in same directory
│       │   └── ...
│       └── swift-swiftui/
│           ├── SKILL.md
│           └── ...
```

**Critical conventions:**
1. `marketplace.json` goes in **root** `.claude-plugin/` — contains `"plugins"` array pointing to `"source": "./plugin"`
2. `plugin.json` goes in **`plugin/.claude-plugin/`** — minimal: `name`, `version`, `description`, `author`
3. Skills go in **`plugin/skills/<skill-name>/SKILL.md`** — NOT inside `.claude-plugin/`
4. SKILL.md must have YAML frontmatter with `name`, `description`, `user-invocable: true`
5. Supporting markdown files live alongside SKILL.md in the same directory
6. The `plugin/` directory is the distributable unit — it gets cached when installed

**marketplace.json example (from swift-app-architecture):**
```json
{
  "name": "gestrich-swift-app-architecture",
  "version": "1.0.0",
  "description": "Architectural patterns and best practices for Swift application development",
  "owner": {
    "name": "Bill Gestrich",
    "url": "https://github.com/gestrich"
  },
  "plugins": [
    {
      "name": "swift-app-architecture",
      "source": "./plugin",
      "description": "...",
      "version": "1.0.0",
      "category": "development"
    }
  ]
}
```

**plugin.json example (from swift-app-architecture):**
```json
{
  "name": "swift-app-architecture",
  "version": "1.0.0",
  "description": "Architectural patterns and best practices for Swift application development",
  "author": {
    "name": "Bill Gestrich",
    "url": "https://github.com/gestrich"
  },
  "keywords": ["swift", "architecture", "ios", "best-practices"]
}
```

### Claude Plugin Best Practices (from official docs)

Key documentation findings that inform our approach:

1. **Skill arguments**: Skills accept user input via `$ARGUMENTS` placeholder in the description or body. Invoke with `/plugin-name:skill-name <args>`.

2. **Plugin root variable**: Scripts can use `${CLAUDE_PLUGIN_ROOT}` to reference the plugin's root directory. This is useful for the Python CLI path.

3. **Plugin caching**: When installed, plugins are copied to a cache directory (`~/.claude/plugins/cache/`). Paths cannot reference files outside the plugin directory. This means the Python CLI **must** live inside the plugin directory structure to be accessible.

4. **Auto-discovery**: If `plugin.json` exists, Claude Code auto-discovers `commands/`, `agents/`, `skills/` at the plugin root. Custom paths in plugin.json supplement default directories.

5. **Installation scopes**: `--scope user` (all projects), `--scope project` (team-wide), `--scope local` (personal, this project only).

6. **Local testing**: `claude --plugin-dir ./path/to/plugin` loads the plugin for development testing.

### Configuration Strategy

The plugin skills need app-specific configuration. The approach:

**Host app creates `.xcuitest-config.json` in the project root:**

```json
{
  "xcodeProject": "PRRadar.xcodeproj",
  "scheme": "PRRadarMac",
  "destination": "platform=macOS",
  "uiTestTarget": "PRRadarMacUITests",
  "testClass": "InteractiveControlTests",
  "testMethod": "testInteractiveControl",
  "containerPath": "~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp",
  "processName": "PRRadarMac",
  "appSpecificNotes": "navigation-patterns.md"
}
```

The plugin skills read this file at invocation time, filling in the generic templates with app-specific values. If no config file exists, skills fall back to placeholder prompts asking the user for the values.

The `appSpecificNotes` field points to an optional markdown file in the host project (e.g., `.claude/xcuitest-notes.md`) with app-specific navigation patterns, accessibility identifiers, and other context that doesn't belong in the generic plugin.

## Phases

## - [x] Phase 1: Create Plugin Structure in xcode-sim-automation

**Repo**: `~/Developer/personal/xcode-sim-automation`

Create the plugin directory structure following the swift-app-architecture pattern exactly:

```
xcode-sim-automation/
├── .claude-plugin/
│   └── marketplace.json
├── plugin/
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── LICENSE
│   ├── tools/
│   │   └── xcuitest-control.py       ← Copy from Tools/
│   └── skills/
│       ├── interactive-xcuitest/
│       │   ├── SKILL.md
│       │   ├── cli-reference.md
│       │   ├── error-handling.md
│       │   └── macos-notes.md
│       └── creating-automated-screenshots/
│           ├── SKILL.md
│           ├── test-patterns.md
│           └── element-discovery.md
├── .claude/
│   └── skills/                        ← Keep existing internal skills for local dev
│       ├── interactive-xcuitest/
│       └── creating-automated-screenshots/
├── Tools/
│   └── xcuitest-control.py            ← Keep original location too
├── Sources/
│   └── XCUITestControl/               ← Swift library (unchanged)
└── Package.swift                       ← Swift library (unchanged)
```

**Files to create:**

1. `.claude-plugin/marketplace.json`:
   - `name`: `"gestrich-xcode-sim-automation"`
   - Plugin name: `"xcode-sim-automation"`
   - `source`: `"./plugin"`

2. `plugin/.claude-plugin/plugin.json`:
   - `name`: `"xcode-sim-automation"`
   - `keywords`: `["xcuitest", "automation", "ui-testing", "screenshots"]`

3. `plugin/LICENSE` — MIT license (copy from swift-app-architecture)

4. `plugin/tools/xcuitest-control.py` — Copy of `Tools/xcuitest-control.py`. The Python CLI must be inside the plugin directory since installed plugins are cached and can't reference outside files.

**Completed**: Structure created with all 4 files. Skill directories contain `.gitkeep` placeholders — SKILL.md files will be added in Phase 2. Swift build verified unaffected.

## - [x] Phase 2: Create Plugin Skills (Generic + Config-Aware)

**Repo**: `~/Developer/personal/xcode-sim-automation`

Create the plugin versions of both skills. These are the **authoritative, reusable** versions that read from `.xcuitest-config.json` when present and fall back to generic instructions when not.

### interactive-xcuitest skill

Split the current 643-line PRRadar skill into a modular structure:

**`plugin/skills/interactive-xcuitest/SKILL.md`** — Main skill file:
- YAML frontmatter (`name`, `description`, `user-invocable: true`)
- Overview and usage section
- Config loading instructions: "Read `.xcuitest-config.json` from the project root to get app-specific settings. If the file doesn't exist, ask the user for the Xcode project, scheme, destination, and container path."
- High-level workflow (setup vars, kill stale processes, build, start test, wait, activate, execute, exit)
- Links to supporting docs

**`plugin/skills/interactive-xcuitest/cli-reference.md`** — Full CLI command reference:
- All commands (tap, scroll, type, adjust, wait, screenshot, status, activate, reset, ready, done)
- CLI output format
- `--container` flag documentation
- Multiple match handling
- File-based protocol (advanced)

**`plugin/skills/interactive-xcuitest/error-handling.md`** — Error handling and troubleshooting:
- Common errors table
- Recovery procedures
- Robustness configuration

**`plugin/skills/interactive-xcuitest/macos-notes.md`** — macOS-specific guidance:
- No simulator needed
- Sandbox and file paths (must use `--container`)
- Window visibility/focus
- Kill stale processes
- Orphaned processes cleanup
- Automation mode timeout
- "Automation Running" notification explanation
- Build-first pattern

### creating-automated-screenshots skill

Split into modular structure:

**`plugin/skills/creating-automated-screenshots/SKILL.md`** — Main skill file:
- YAML frontmatter
- Overview and workflow
- Config loading instructions (same pattern)
- Test file template (generic version)
- Build and run instructions
- Screenshot extraction

**`plugin/skills/creating-automated-screenshots/test-patterns.md`** — Test creation patterns:
- `captureHierarchy` helper
- `findTappable` helper
- Navigation step patterns (tab bar, table/list, sheets, multi-step)
- Assertion requirements for every step
- Build-first pattern

**`plugin/skills/creating-automated-screenshots/element-discovery.md`** — Element type guidance:
- Element types vs visual appearance table
- Hierarchy reading examples
- Iterative debugging workflow

### Config Loading Pattern

Both skills should start with this pattern:

```markdown
## Configuration

Read `.xcuitest-config.json` from the project root. If it exists, use its values throughout this skill:

- `$PROJECT` = config.xcodeProject (e.g., "PRRadar.xcodeproj")
- `$SCHEME` = config.scheme (e.g., "PRRadarMac")
- `$DESTINATION` = config.destination (e.g., "platform=macOS")
- `$UI_TEST_TARGET` = config.uiTestTarget (e.g., "PRRadarMacUITests")
- `$TEST_CLASS` = config.testClass (e.g., "InteractiveControlTests")
- `$TEST_METHOD` = config.testMethod (e.g., "testInteractiveControl")
- `$CONTAINER` = config.containerPath (e.g., "~/Library/Containers/.../Data/tmp")
- `$PROCESS_NAME` = config.processName (e.g., "PRRadarMac")

If `.xcuitest-config.json` doesn't exist, ask the user for these values before proceeding.

If `config.appSpecificNotes` is set, read that file from the project root for app-specific navigation patterns and accessibility identifiers.
```

The Python CLI path uses the plugin's own `tools/` directory. Since the plugin is installed locally or from marketplace, the skill should reference:
```
python3 <plugin-tools-dir>/xcuitest-control.py
```

Where `<plugin-tools-dir>` is determined by the skill at runtime. The simplest approach: the SKILL.md instructs Claude to locate the Python CLI by searching for the xcode-sim-automation package (checking common locations or using the config).

**Completed**: Both skills created with modular structure. The interactive-xcuitest skill was split into SKILL.md (main workflow + config loading), cli-reference.md (all commands + multiple match handling + file protocol), error-handling.md (robustness config + common errors + troubleshooting), and macos-notes.md (sandbox, window focus, build-first, orphaned processes). The creating-automated-screenshots skill was split into SKILL.md (workflow + test template + extraction), test-patterns.md (helpers + navigation patterns + assertions), and element-discovery.md (type mismatches + hierarchy reading + iterative debugging). Both skills use the config loading pattern with `$PROJECT`, `$SCHEME`, etc. variables from `.xcuitest-config.json`. `.gitkeep` placeholders removed. Swift build verified unaffected.

## - [x] Phase 3: Create PRRadar Configuration

**Repo**: `~/Developer/personal/PRRadar`

1. **Create `.xcuitest-config.json`** in the PRRadar project root:
   ```json
   {
     "xcodeProject": "PRRadar.xcodeproj",
     "scheme": "PRRadarMac",
     "destination": "platform=macOS",
     "uiTestTarget": "PRRadarMacUITests",
     "testClass": "InteractiveControlTests",
     "testMethod": "testInteractiveControl",
     "containerPath": "~/Library/Containers/org.gestrich.PRRadarMacUITests.xctrunner/Data/tmp",
     "processName": "PRRadarMac",
     "appSpecificNotes": ".claude/xcuitest-notes.md"
   }
   ```

2. **Create `.claude/xcuitest-notes.md`** with PRRadar-specific content extracted from the current skills:
   - Three-column NavigationSplitView layout diagram
   - Column descriptions (Config Sidebar, PR List, Detail View)
   - Navigation steps for common views (Summary, Diff, Report, Settings)
   - Known accessibility identifiers (settingsButton, refreshButton, configRow_*, prRow_*, phaseButton_*, etc.)
   - PRRadar-specific tips (e.g., "the `done` command will report a timeout — this is expected")

3. **Remove `.claude/skills/interactive-xcuitest/`** from PRRadar (now provided by plugin)

4. **Remove `.claude/skills/creating-automated-screenshots/`** from PRRadar (now provided by plugin)

5. **Update `CLAUDE.md`** — Change skill references from local skills to plugin skills:
   - `/interactive-xcuitest` → `/xcode-sim-automation:interactive-xcuitest`
   - `/creating-automated-screenshots` → `/xcode-sim-automation:creating-automated-screenshots`

**Completed**: Created `.xcuitest-config.json` with all 9 config fields. Created `.claude/xcuitest-notes.md` with PRRadar-specific content: three-column NavigationSplitView layout diagram, column descriptions, navigation steps for Summary/Diff/Report/Settings views, accessibility identifier table, app-specific tips (done timeout, stale process cleanup, orphaned processes), and screenshot test patterns with common navigation code. Removed both local skills (`interactive-xcuitest` and `creating-automated-screenshots`). Updated `CLAUDE.md` to reference plugin skills (`/xcode-sim-automation:interactive-xcuitest` and `/xcode-sim-automation:creating-automated-screenshots`).

## - [x] Phase 4: Install and Test Plugin

**Repos**: Both

1. **Test plugin locally** from PRRadar:
   ```bash
   claude --plugin-dir ~/Developer/personal/xcode-sim-automation/plugin
   ```
   Verify both skills appear in the skill list.

2. **Test skill invocation**: Run `/xcode-sim-automation:interactive-xcuitest` and verify it:
   - Reads `.xcuitest-config.json` correctly
   - Reads `.claude/xcuitest-notes.md` for app-specific context
   - Shows correct Xcode project, scheme, container paths
   - Locates the Python CLI

3. **Test screenshot skill**: Run `/xcode-sim-automation:creating-automated-screenshots` and verify similar behavior.

4. **Install via marketplace** (optional, if marketplace is set up):
   ```bash
   /plugin marketplace add gestrich/xcode-sim-automation
   claude plugin install xcode-sim-automation@gestrich-xcode-sim-automation --scope local
   ```

**Completed**: All tests passed:

- **Plugin loading**: `claude --plugin-dir ~/Developer/personal/xcode-sim-automation/plugin` loads successfully. Both skills (`xcode-sim-automation:interactive-xcuitest` and `xcode-sim-automation:creating-automated-screenshots`) appear in the skill list.
- **interactive-xcuitest skill**: Reads all 9 values from `.xcuitest-config.json` correctly (xcodeProject, scheme, destination, uiTestTarget, testClass, testMethod, containerPath, processName, appSpecificNotes). Reads `.claude/xcuitest-notes.md` and finds all 8 sections (UI Layout, Column descriptions, Navigation Steps, Accessibility Identifiers, PRRadar-Specific Tips, Screenshot Test Patterns, etc.).
- **creating-automated-screenshots skill**: Same config reading verified — all 9 values from `.xcuitest-config.json` and `.claude/xcuitest-notes.md` sections confirmed.
- **Python CLI location**: Found at both `~/Developer/personal/xcode-sim-automation/Tools/xcuitest-control.py` and `plugin/tools/xcuitest-control.py` when `--add-dir` grants access to the xcode-sim-automation repo. Note: When using `--plugin-dir` alone, the sandbox restricts file access to the current project directory, so `--add-dir ~/Developer/personal/xcode-sim-automation` is needed for the CLI to be located.
- **Marketplace install**: Skipped (not set up yet).

## - [ ] Phase 5: Clean Up and Commit

**Repos**: Both

1. **xcode-sim-automation repo**:
   - Commit the new plugin structure
   - Keep `.claude/skills/` (internal dev skills) alongside `plugin/skills/` (published plugin skills)
   - Keep `Tools/xcuitest-control.py` at original location (for direct usage) alongside `plugin/tools/xcuitest-control.py` (for plugin usage)
   - Push to GitHub

2. **PRRadar repo**:
   - Commit removal of local skills
   - Commit new config files (`.xcuitest-config.json`, `.claude/xcuitest-notes.md`)
   - Commit CLAUDE.md updates

## - [ ] Phase 6: Validation

1. **Plugin loading**: Verify the plugin loads without errors:
   ```bash
   claude --plugin-dir ~/Developer/personal/xcode-sim-automation/plugin
   # Check /plugin list shows xcode-sim-automation
   ```

2. **Skill discovery**: Verify both skills appear:
   - `/xcode-sim-automation:interactive-xcuitest`
   - `/xcode-sim-automation:creating-automated-screenshots`

3. **Config reading**: Invoke a skill and verify it reads `.xcuitest-config.json` and `.claude/xcuitest-notes.md`

4. **End-to-end**: Run the interactive-xcuitest skill against PRRadar and verify the full workflow works (build, start test, interact, exit) — same as before but now using the plugin skill instead of the local skill

5. **No regressions**: Confirm the existing xcode-sim-automation Swift library and Python CLI still work independently (no changes to package functionality)
