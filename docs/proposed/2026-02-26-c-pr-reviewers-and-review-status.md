## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules, dependency flow, use case patterns, code style |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, @Observable models, enum-based state, dependency injection |
| `swift-testing` | Test style guide and conventions |

## Background

PRRadar currently fetches review data (`GitHubReview` with state/author) but doesn't expose requested reviewers or aggregate review statuses in the UI. GitHub shows a "Reviewers" sidebar with each reviewer's avatar, name, and review status (pending, approved, changes requested, commented, dismissed). Users want this same experience in PRRadar, plus the ability to submit their own review (approve, request changes, or comment) directly from the app.

Key requirements from Bill:
- Show requested reviewers and their review status (approved, changes requested, commented, pending)
- Display GitHub avatar photos for reviewers (cached locally)
- Allow submitting a review (approve, request changes, comment with body text)
- Use cases must power this so both the MacApp and CLI can use the same logic
- Behavior should mirror the GitHub website review experience

### What Already Exists

**OctoKit provides:**
- `PullRequest.requestedReviewers: [User]?` — users requested but haven't reviewed yet
- `User.avatarURL: String?` — GitHub avatar URL on user objects
- `Review` model with `state` (APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED, PENDING), `user`, `body`, `submittedAt`
- `Octokit.postReview()` — submit a new review with event (APPROVE, REQUEST_CHANGES, COMMENT) and body
- `Octokit.reviews()` — list all reviews on a PR

**PRRadar already:**
- Fetches `[GitHubReview]` via `GitHubService.getPullRequestComments()` and stores in `GitHubPullRequestComments.reviews`
- Has `GitHubAuthor` model (login, id, name) but no avatar URL
- Has `ImageDownloadService` for downloading/caching images to disk
- Has `AuthorCacheService` for caching author display names

### GitHub Reviewer Status Logic

GitHub computes per-reviewer status by taking the **latest non-PENDING, non-DISMISSED review** for each user. If a user is in `requested_reviewers`, they show as "Pending" regardless of prior reviews (re-request clears their status). The display priority is: requested (pending) > latest review state.

## Phases

## - [ ] Phase 1: Domain Models — Reviewer and Avatar Support

**Skills to read**: `swift-app-architecture:swift-architecture`

Add `avatarURL` to `GitHubAuthor` and create a new `PRReviewerStatus` model.

**Models layer** (`PRRadarModels`):

1. Add `avatarURL: String?` field to `GitHubAuthor` (with corresponding init parameter and Codable support)
2. Create `PRReviewerStatus` model:
   ```
   struct PRReviewerStatus: Codable, Sendable, Identifiable {
       let login: String
       let name: String?
       let avatarURL: String?
       let status: ReviewStatus
       let latestReviewBody: String?
       let latestReviewDate: String?
   }

   enum ReviewStatus: String, Codable, Sendable {
       case pending        // Requested but no review yet
       case approved       // APPROVED
       case changesRequested // CHANGES_REQUESTED
       case commented      // COMMENTED
       case dismissed      // DISMISSED
   }
   ```
3. Create `PRReviewSummary` model:
   ```
   struct PRReviewSummary: Codable, Sendable {
       let reviewers: [PRReviewerStatus]
       let approvalCount: Int
       let changesRequestedCount: Int
       let pendingCount: Int
   }
   ```

**Update `GitHubPullRequest`:**
4. Add `requestedReviewers: [GitHubAuthor]?` field to `GitHubPullRequest`

## - [ ] Phase 2: SDK Layer — Requested Reviewers and Review Submission

**Skills to read**: `swift-app-architecture:swift-architecture`

Expose requested reviewers and review submission in `OctokitClient`.

1. Update `OctokitClient.pullRequest()` — the OctoKit `PullRequest` already has `requestedReviewers: [User]?`, so this data is already returned. Extract it in the conversion.
2. Add `OctokitClient.postReview()` method wrapping OctoKit's `postReview()`:
   ```swift
   public func postReview(
       owner: String, repository: String, number: Int,
       event: Review.Event, body: String?
   ) async throws -> Review
   ```
3. Add avatar URL extraction — OctoKit's `User.avatarURL` is already present. Ensure it flows through the `PullRequest` → `GitHubPullRequest` conversion for both the PR author and requested reviewers.

## - [ ] Phase 3: Service Layer — ReviewerService and Avatar Caching

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a service that computes reviewer status and manages avatar caching.

**GitHubService updates:**
1. Add `getRequestedReviewers(number:)` — extract from the PR's `requestedReviewers` field
2. Add `submitReview(number:event:body:)` — wraps `OctokitClient.postReview()`
3. Update `getPullRequest()` to populate `requestedReviewers` on `GitHubPullRequest`

**New `AvatarCacheService`** (in `PRRadarCLIService`):
4. Manages avatar downloads to `<outputDir>/<prNumber>/metadata/avatars/`
5. Uses `<login>.png` as filename for deterministic cache lookup
6. `downloadAvatar(login:avatarURL:outputDir:prNumber:) -> String?` — returns local path if cached or downloaded
7. `localAvatarPath(login:outputDir:prNumber:) -> String?` — checks cache without downloading
8. Avatars are small (GitHub serves them at configurable sizes via `?s=64` query param), so download at 64px

**New `ReviewerStatusService`** (in `PRRadarCLIService`):
9. `computeReviewSummary(requestedReviewers:reviews:) -> PRReviewSummary` — pure function that:
   - Groups reviews by user login
   - Takes latest non-PENDING review per user
   - Marks users in `requestedReviewers` as `.pending` (overrides prior reviews)
   - Returns `PRReviewSummary` with aggregated counts

## - [ ] Phase 4: Feature Layer — Use Cases

**Skills to read**: `swift-app-architecture:swift-architecture`

Create use cases that both MacApp and CLI can use.

1. **`FetchReviewStatusUseCase`** — fetches PR, reviews, and requested reviewers; computes `PRReviewSummary`; downloads avatars:
   ```swift
   struct FetchReviewStatusUseCase {
       let config: RepositoryConfiguration
       func execute(prNumber: Int) async throws -> PRReviewSummary
   }
   ```
   - Calls `GitHubService.getPullRequest()` for requested reviewers
   - Calls `GitHubService.getPullRequestComments()` for reviews
   - Uses `ReviewerStatusService` to compute summary
   - Uses `AvatarCacheService` to download/cache avatars
   - Saves summary to `<outputDir>/<prNumber>/metadata/review-summary.json`

2. **`SubmitReviewUseCase`** — submits a review to GitHub:
   ```swift
   struct SubmitReviewUseCase {
       let config: RepositoryConfiguration
       func execute(prNumber: Int, event: ReviewStatus, body: String?) async throws
   }
   ```
   - Maps `ReviewStatus` → OctoKit `Review.Event`
   - Calls `GitHubService.submitReview()`
   - After submission, refreshes reviewer status (calls `FetchReviewStatusUseCase`)

3. **`LoadReviewStatusUseCase`** — loads cached `PRReviewSummary` from disk (sync, no network):
   ```swift
   struct LoadReviewStatusUseCase {
       let config: RepositoryConfiguration
       func execute(prNumber: Int) -> PRReviewSummary?
   }
   ```

## - [ ] Phase 5: CLI Commands — `reviewers` and `review`

**Skills to read**: `swift-app-architecture:swift-architecture`

Add CLI commands that use the new use cases.

1. **`reviewers` command** — shows reviewer status:
   ```
   swift run PRRadarMacCLI reviewers 1 --config test-repo
   ```
   Output (text mode):
   ```
   Reviewers for PR #1:
     jane-doe     ✅ Approved (2026-02-25)
     john-smith   ❌ Changes Requested (2026-02-24)
     alice-wong   ⏳ Pending

   Summary: 1 approved, 1 changes requested, 1 pending
   ```
   JSON mode (`--json`) outputs `PRReviewSummary` as JSON.

2. **`review` command** — submits a review:
   ```
   swift run PRRadarMacCLI review 1 --config test-repo --approve
   swift run PRRadarMacCLI review 1 --config test-repo --request-changes --body "Please fix the null check"
   swift run PRRadarMacCLI review 1 --config test-repo --comment --body "Looks good overall"
   ```
   Uses `SubmitReviewUseCase`. Exactly one of `--approve`, `--request-changes`, or `--comment` is required.

## - [ ] Phase 6: MacApp Model Layer — PRModel Integration

**Skills to read**: `swift-app-architecture:swift-swiftui`

Integrate reviewer status into the existing `PRModel`.

1. Add `reviewSummary: PRReviewSummary?` property to `PRModel`
2. Add `reviewSubmissionState: ReviewSubmissionState` enum (`.idle`, `.submitting`, `.submitted`, `.failed(String)`)
3. Load cached `PRReviewSummary` in `reloadDetail()` via `LoadReviewStatusUseCase`
4. Add `fetchReviewStatus()` async method — calls `FetchReviewStatusUseCase`, updates `reviewSummary`
5. Add `submitReview(event:body:)` async method — calls `SubmitReviewUseCase`, refreshes status after
6. Trigger `fetchReviewStatus()` during `refreshPRData()` alongside existing diff refresh
7. Avatar images loaded from disk using local paths from `PRReviewerStatus`

## - [ ] Phase 7: MacApp UI — Reviewer Panel and Review Submission

**Skills to read**: `swift-app-architecture:swift-swiftui`

Build the reviewer UI in the MacApp.

1. **`ReviewerAvatarView`** — displays a single reviewer's avatar (circular, 24pt):
   - Loads image from local cached file path
   - Falls back to initials circle (first letter of login) if no avatar
   - Overlay badge for status (green checkmark for approved, red X for changes requested, orange clock for pending)

2. **`ReviewerStatusRow`** — full row for a reviewer:
   - Avatar + name/login + status badge + review date
   - Styled similarly to GitHub's reviewer sidebar

3. **`ReviewersPanel`** — complete reviewer list:
   - Shows all reviewers from `PRReviewSummary`
   - Summary line at top ("1 of 3 approved")
   - Refresh button to re-fetch from GitHub

4. **`SubmitReviewView`** — sheet/popover for submitting a review:
   - Radio buttons or segmented control: Approve / Request Changes / Comment
   - Text editor for review body (required for Request Changes, optional for others)
   - Submit button with loading state
   - Dismiss on success

5. **Integration into `ReviewDetailView`**:
   - Add `ReviewersPanel` to the PR header area or as a sidebar section
   - Add "Submit Review" button in the header that opens `SubmitReviewView`

## - [ ] Phase 8: Data Flow — Sync and Refresh Integration

**Skills to read**: `swift-app-architecture:swift-architecture`

Integrate reviewer fetching into the existing sync/refresh pipeline.

1. Update `SyncPRUseCase` to also fetch reviewer status during the metadata phase
2. Save `review-summary.json` alongside `gh-pr.json` and `gh-comments.json` in metadata
3. Save avatars to `<outputDir>/<prNumber>/metadata/avatars/`
4. Update `LoadPRDetailUseCase` to load `PRReviewSummary` from disk
5. Update `PRDetail` to include `reviewSummary: PRReviewSummary?`

## - [ ] Phase 9: Validation

**Skills to read**: `swift-testing`

1. **Unit tests for `ReviewerStatusService.computeReviewSummary()`**:
   - Requested reviewer with no reviews → pending
   - Single approved review → approved
   - Multiple reviews from same user → latest wins
   - Re-requested reviewer (in requestedReviewers list) → pending even with prior approval
   - Mixed statuses → correct counts in summary

2. **Unit tests for `PRReviewerStatus` and `PRReviewSummary`**:
   - Codable round-trip encoding/decoding
   - Computed properties (approvalCount, etc.)

3. **Unit tests for `GitHubAuthor` avatar enrichment**:
   - `withAvatarURL()` or verify avatarURL flows through conversions

4. **Build verification**: `swift build` succeeds

5. **Test suite**: `swift test` passes with no regressions

6. **Manual CLI verification**:
   ```bash
   swift run PRRadarMacCLI reviewers 1 --config test-repo
   swift run PRRadarMacCLI reviewers 1 --config test-repo --json
   ```
