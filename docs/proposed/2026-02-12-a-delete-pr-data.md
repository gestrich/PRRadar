## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules, layer responsibilities, dependency rules, placement guidance |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, enum-based state, observable model conventions |
| `/swift-testing` | Test style guide and conventions |

## Background

The MacApp toolbar has buttons for refresh, analyze, open in Finder, and open on GitHub. There's no way to clear a PR's local data and start fresh. This adds a trash icon button with a confirmation popover that deletes all local data for the selected PR, then re-fetches it from GitHub.

**Key design decision**: Rather than resetting all PRModel properties after deletion (fragile — breaks silently if new properties are added later), the use case deletes disk data, re-fetches from GitHub, and returns a fully-formed result. The caller creates a brand-new PRModel to replace the old one in the array.

### Key files and patterns discovered

- **Toolbar**: `ContentView.swift:41-106` — `ToolbarItemGroup(placement: .primaryAction)` holds PR-specific buttons (refresh, analyze, folder, safari)
- **Popover pattern**: `@State` bool + `.popover(isPresented:arrowEdge:)` on a button (e.g., `showAnalyzeAll`, `showNewReview`)
- **PR array**: `AllPRsModel.state` holds `[PRModel]` in `.ready`/`.refreshing` cases; `currentPRModels` computed property extracts them
- **PRModel.init**: Takes `(metadata: PRMetadata, config: PRRadarConfig, repoConfig: RepoConfiguration)` and automatically calls `Task { reloadDetail() }` to load from disk
- **Use case pattern**: `Sendable` struct with `private let config: PRRadarConfig`, public init, `execute()` method
- **SyncPRUseCase**: Already handles single-PR fetch from GitHub (metadata + diff + comments), writes to disk, returns `SyncSnapshot` via `AsyncThrowingStream`
- **PRDiscoveryService**: Scans output directory, reads `gh-pr.json`, returns `[PRMetadata]` — reusable for reading freshly-written metadata after re-fetch
- **PR data on disk**: `<config.absoluteOutputDir>/<prNumber>/` containing `metadata/` and `analysis/<commitHash>/` subdirectories

## Phases

## - [x] Phase 1: Create `DeletePRDataUseCase`

**Skills to read**: `/swift-app-architecture:swift-architecture`

**Create** `PRRadarLibrary/Sources/features/PRReviewFeature/usecases/DeletePRDataUseCase.swift`

Async use case in the Features layer that:
1. Deletes the PR directory (`<config.absoluteOutputDir>/<prNumber>/`) from disk via `FileManager.removeItem`
2. Re-fetches from GitHub by consuming `SyncPRUseCase(config:).execute(prNumber:)` stream
3. Reads the freshly-written metadata via `PRDiscoveryService.discoverPRs()` and finds the matching PR
4. Returns `PRMetadata` — everything the caller needs to create a replacement PRModel

Error handling:
- No-op if directory doesn't exist (user may delete a PR that was never fetched)
- Throws on filesystem errors
- Throws if the SyncPRUseCase stream yields `.failed`
- Falls back to `PRMetadata.fallback(number:)` if metadata can't be read after re-fetch

Dependencies: `PRRadarConfigService` (already a dependency of `PRReviewFeature`), `SyncPRUseCase`, `PRDiscoveryService`, `PRRadarModels`.

## - [x] Phase 2: Add `deletePRData(for:)` to `AllPRsModel`

**Skills to read**: `/swift-app-architecture:swift-swiftui`

**Modify** `PRRadarLibrary/Sources/apps/MacApp/Models/AllPRsModel.swift`

Add a new method:
- Calls `DeletePRDataUseCase(config:).execute(prNumber:)` to delete + re-fetch
- Creates a new `PRModel(metadata:config:repoConfig:)` from the returned metadata
- Finds the old PRModel in `currentPRModels` by `id` and replaces it in the array
- Sets `state = .ready(updatedModels)`
- Returns the replacement PRModel so the caller can update `selectedPR`

The new PRModel's init automatically triggers `Task { reloadDetail() }`, loading detail from the freshly-written disk data. No manual property reset needed.

**Completed**: Added `deletePRData(for:)` as a `@discardableResult` async throwing method. Takes a `PRModel`, delegates to `DeletePRDataUseCase`, creates a replacement `PRModel`, swaps it into the array, and returns it.

## - [x] Phase 3: Add trash button and confirmation popover to `ContentView`

**Skills to read**: `/swift-app-architecture:swift-swiftui`

**Modify** `PRRadarLibrary/Sources/apps/MacApp/UI/ContentView.swift`

**State variables**: Add `@State private var showDeleteConfirmation = false` and `@State private var isDeletingPR = false`.

**Trash button**: Add inside `ToolbarItemGroup(placement: .primaryAction)` after the safari button:
- Icon: `"trash"` (shows `ProgressView` when `isDeletingPR`)
- `.accessibilityIdentifier("deleteButton")`
- `.help("Delete all local data for this PR")`
- Disabled when: `isDeletingPR`, no PR selected, any phase running, or empty PR number
- `.popover(isPresented: $showDeleteConfirmation, arrowEdge: .bottom)` attached to the button

**Confirmation popover** (`deleteConfirmationPopover` computed property):
- "Delete PR Data" headline
- Description: "All local review data for PR #X will be deleted and re-fetched from GitHub."
- Cancel button (`.cancelAction`) + Delete button (`role: .destructive`, `.defaultAction`)
- On delete: dismiss popover, set `isDeletingPR = true`, call `allPRs?.deletePRData(for:)`, update `selectedPR` to the returned replacement, set `isDeletingPR = false`

**Disable other buttons during deletion**: Add `isDeletingPR` to the disabled conditions on refresh, analyze, folder, and safari toolbar buttons.

**Completed**: Added trash button as the last item in the primary action toolbar group. Popover uses `deleteConfirmationPopover` computed property with Cancel/Delete buttons. Delete action uses `try? await` to silently handle errors (matching the pattern where the UI shows the spinner and resets gracefully). All four existing toolbar buttons (refresh, analyze, folder, safari) now include `isDeletingPR` in their disabled conditions.

## - [x] Phase 4: Validation

**Skills to read**: `/swift-testing`

1. `cd PRRadarLibrary && swift build` — confirms compilation across all targets
2. `swift test` — confirms no regressions in existing 431 tests
3. Manual verification: select a PR in MacApp, click trash, confirm deletion, verify spinner appears, data re-fetches, and detail view refreshes with clean state

**Completed**: Build succeeded (all targets compile). All 431 tests in 46 suites passed with no regressions. Manual verification deferred to Bill.
