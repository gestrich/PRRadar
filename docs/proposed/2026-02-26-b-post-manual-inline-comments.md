## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-app-architecture:swift-architecture` | 4-layer architecture rules (placement, dependency rules) |
| `/swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns (observable models, state management) |
| `/swift-testing` | Test style guide and conventions |

## Background

Bill wants the ability to post manual inline comments on PR diffs — both from the MacApp GUI and from the CLI. Currently, comments can only be posted from AI-generated violations (PRComment objects with rule metadata). This feature adds freeform comment authoring directly from the diff view.

**GUI flow**: Hover over a line number in the diff → a "+" button appears in the gutter → click it → an inline compose view appears below that line (styled similarly to InlineCommentView but with a text editor) → type comment text → hit Send → the comment is posted to GitHub → comments are re-fetched from GitHub → the new comment appears as a posted comment (InlinePostedCommentView).

**CLI flow**: A new `post-comment` subcommand posts a single comment given PR number, file path, line number, and body text.

**Key architectural context**:
- `DiffLineRowView` already has `@State private var isHovering` but doesn't use it visually yet
- `AnnotatedHunkContentView` renders comments inline after diff lines, keyed by `newLineNumber`
- `CommentService.postReviewComment()` and `GitHubService.postReviewComment()` handle the actual GitHub API call
- `PostSingleCommentUseCase` exists but requires a `PRComment` (with rule metadata) — we need something that takes raw body text
- `FetchReviewCommentsUseCase` loads posted comments from the **disk cache** (`metadata/gh-comments.json`), not directly from GitHub
- `PRAcquisitionService.acquire()` fetches comments from GitHub via `gitHub.getPullRequestComments()` and writes them to `metadata/gh-comments.json` — we should extract/reuse that same fetch-and-save logic inside `FetchReviewCommentsUseCase` behind a flag, rather than creating a separate use case

## Phases

## - [x] Phase 1: PostManualCommentUseCase (Feature Layer)

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Followed existing `PostSingleCommentUseCase` pattern; calls `GitHubService.postReviewComment()` directly (no `CommentService`/`PRComment` needed for raw text)

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a new use case in `Sources/features/PRReviewFeature/usecases/` that posts a freeform comment to a GitHub PR at a specific file and line.

**PostManualCommentUseCase**:
- Input: `prNumber: Int`, `filePath: String`, `lineNumber: Int`, `body: String`, `commitSHA: String`
- Creates `GitHubService` via `GitHubServiceFactory`
- Creates `CommentService` and calls `postReviewComment` using a minimal `PRComment` or calls `GitHubService.postReviewComment()` directly with raw body
- Prefer calling `GitHubService.postReviewComment(number:commitId:path:line:body:)` directly since we have raw text (no rule markdown formatting needed)
- Returns `Bool` (success/failure)
- File: `PostManualCommentUseCase.swift`

## - [x] Phase 2: Extend FetchReviewCommentsUseCase with Network Refresh

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Extracted `refreshComments()` on `PRAcquisitionService` so both `acquire()` and `FetchReviewCommentsUseCase` share the same fetch+save code path. Used overloaded `execute()` (sync vs async with `cachedOnly:`) to avoid cascading async changes to existing sync callers.

**Skills to read**: `swift-app-architecture:swift-architecture`

Add a `refreshFromGitHub: Bool` parameter (default `false`) to `FetchReviewCommentsUseCase.execute()`. When `true`, it fetches comments from the GitHub API and writes them to `metadata/gh-comments.json` **before** doing the normal disk-based load and reconciliation.

**Changes to FetchReviewCommentsUseCase**:
- Add `refreshFromGitHub: Bool = false` parameter to `execute()`
- When `refreshFromGitHub` is true:
  - Create `GitHubService` via `GitHubServiceFactory`
  - Call `gitHub.getPullRequestComments(number:)` — same call that `PRAcquisitionService.acquire()` uses
  - Optionally resolve author names via `AuthorCacheService` (follow pattern from `PRAcquisitionService`)
  - Encode result as JSON and write to `metadata/gh-comments.json` using `DataPathsService`
- Then proceed with the existing disk-based load flow (which now reads the freshly-written file)
- Make `execute()` `async` when `refreshFromGitHub` is true (the existing sync path stays sync — or just make the whole method async since the callers can handle it)

**Extract from PRAcquisitionService**: The comment-fetching and writing logic in `PRAcquisitionService.acquire()` (lines ~84-99, 118-119) should be extracted into a shared helper (e.g., a static method on a service, or inline in `FetchReviewCommentsUseCase`) so both `PRAcquisitionService` and `FetchReviewCommentsUseCase` use the same code path for fetching+saving comments.

## - [x] Phase 3: PRModel Integration

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Compose-target tracking and posting-in-progress are view state (`@State`), not model state. The model only exposes the data operation. Updated Phases 4-6 in spec to reflect this.

**Skills to read**: `swift-app-architecture:swift-swiftui`

Add a method to `PRModel` for posting a manual comment and refreshing comments from GitHub.

**Design note — view state vs model state**: Compose-target tracking (which line has the compose editor open) and posting-in-progress state are **view state** per the SwiftUI MV pattern. They belong in `@State` in the view (Phases 5-6), not in the model. The model only provides the data operation.

**New method**:
- `postManualComment(filePath:lineNumber:body:)` async — calls `PostManualCommentUseCase`, then calls `FetchReviewCommentsUseCase(cachedOnly: false)` which re-fetches from GitHub, saves to disk, and returns the updated `[ReviewComment]`. Assigns the result to `reviewComments`. Uses `fullDiff.commitHash` for the commit SHA.

## - [x] Phase 4: DiffLineRowView "+" Button

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: "+" button is an overlay (no layout shift) on the gutter trailing edge, shown on full-row hover like GitHub. Compose-target state is view state (`@State`) per MV pattern.

**Skills to read**: `swift-app-architecture:swift-swiftui`

Modify `DiffLineRowView` to show a "+" button in the gutter area when hovering, for lines that have a `newLineNumber` (addition or context lines — not deletion lines since those don't exist in the new file).

**Changes to DiffLineRowView**:
- Add callback: `var onAddComment: (() -> Void)?` (nil = no button shown, non-nil = show on hover)
- In the gutter `HStack`, overlay a small "+" button on the new-line-number area when `isHovering && onAddComment != nil`
- The "+" button should be small (matching line height), semi-transparent until hovered directly
- Only show for lines with a non-nil `newLineNumber`

**Changes to AnnotatedHunkContentView**:
- Add `@State private var composingCommentLine: (filePath: String, lineNumber: Int)?` — view state tracking which line has the compose editor open
- Pass an `onAddComment` closure to `DiffLineRowView` that sets `composingCommentLine` to `(hunk.filePath, line.newLine)`

## - [x] Phase 5: InlineCommentComposeView

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Extracted shared `InlineCommentCard` container to eliminate duplicated card styling across all three inline comment views. Compose state (`commentText`, `isPosting`) is view state per MV pattern.

**Skills to read**: `swift-app-architecture:swift-swiftui`

Create a new view `InlineCommentComposeView` that appears inline in the diff below a line when the user clicks "+".

**Styling**: Similar to `InlineCommentView` — black background, rounded rectangle with colored border, padded to align with gutter. Use a distinct border color (e.g., purple or teal) to distinguish from AI-generated (blue) and posted (green) comments.

**Content**:
- `TextEditor` for typing the comment body
- "Cancel" button — calls an `onCancel` closure (sets `composingCommentLine = nil` in the parent)
- "Post Comment" button — calls `prModel.postManualComment(filePath:lineNumber:body:)`, uses `@State private var isPosting = false` to show spinner while posting, clears compose on success
- Disable Post button when text is empty or `isPosting` is true

**File**: `Sources/apps/MacApp/UI/GitViews/InlineCommentComposeView.swift`

## - [x] Phase 6: Show Compose View Inline in Diff

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Compose view renders conditionally based on view state (`composingCommentLine`), consistent with MV pattern. Placed after existing comments and before the next diff line.

**Skills to read**: `swift-app-architecture:swift-swiftui`

Modify `AnnotatedHunkContentView` to render `InlineCommentComposeView` when the compose target matches a line in the hunk.

**Changes**:
- After rendering each `DiffLineRowView` and its existing comments, check if `composingCommentLine` matches `(hunk.filePath, line.newLine)`
- If so, render `InlineCommentComposeView` below that line, passing `onCancel: { composingCommentLine = nil }`
- The compose view should appear between the line's existing comments and the next diff line

## - [ ] Phase 7: CLI post-comment Subcommand

**Skills to read**: `swift-app-architecture:swift-architecture`

Add a new CLI command for posting a manual inline comment.

**Command**: `swift run PRRadarMacCLI post-comment <pr-number> --file <path> --line <number> --body <text>`

**Implementation**:
- New file: `Sources/apps/MacCLI/Commands/PostCommentCommand.swift`
- Uses `PostManualCommentUseCase`
- Needs to resolve commit SHA — use `GitHubService.getPRHeadSHA()` or get it from the cached diff's `commitHash`
- Register in the CLI's command group
- Print success/failure message

## - [ ] Phase 8: Validation

**Skills to read**: `swift-testing`

- `swift build` — verify no compilation errors
- `swift test` — verify all existing tests pass
- Write unit tests for `PostManualCommentUseCase` and the new `refreshFromGitHub` path in `FetchReviewCommentsUseCase` (mock the GitHub service)
- Manual verification: run CLI `post-comment` against the test repo to confirm it works end-to-end
