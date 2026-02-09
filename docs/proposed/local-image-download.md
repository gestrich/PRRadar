# Local Image Download for PR Bodies

## Background

PR descriptions on private GitHub repos embed images using `github.com/user-attachments/assets/<UUID>` URLs. These URLs require browser-based session authentication — they redirect to SSO login when accessed unauthenticated, and return an HTML page (not the image) even with an API token header.

The app's `RichContentView` renders HTML blocks in a `WKWebView` with `baseURL: nil` and no GitHub cookies, so these images silently fail to load.

**Discovery:** GitHub's GraphQL API resolves these URLs when returning `bodyHTML`. The resolved URLs point to `private-user-images.githubusercontent.com/...?jwt=...` — signed S3 URLs that can be downloaded without authentication, but expire after 5 minutes. This means we need to download images at acquisition time and serve them locally.

**Scope:** This applies to PR body images AND comment body images (`gh-comments.json`), since comments can also contain `user-attachments` image URLs.

## Phases

## - [x] Phase 1: Add GraphQL bodyHTML Fetch to SDK Layer

Add a method to `OctokitClient` (SDK layer) that fetches a PR's `bodyHTML` via the GitHub GraphQL API.

**Files modified:**
- `Sources/sdks/PRRadarMacSDK/OctokitClient.swift`

**Tasks:**
- [x] Add a `pullRequestBodyHTML(owner:repository:number:) async throws -> String` method
- [x] Use the existing token-based `URLSession` pattern already in `OctokitClient` to call `https://api.github.com/graphql`
- [x] Query: `{ repository(owner:$o, name:$r) { pullRequest(number:$n) { bodyHTML } } }`
- [x] Return the raw `bodyHTML` string

**Architecture note (SDKs layer):** This is a single API call wrapper — stateless, Sendable, wraps one operation. Correct placement per the architecture guide.

**Technical notes:**
- Uses `POST` to `/graphql` endpoint with parameterized GraphQL query (variables: `$owner`, `$name`, `$number`)
- Handles GraphQL-level errors (returned in `errors` array with HTTP 200) in addition to HTTP-level errors
- Supports enterprise API endpoints via existing `apiEndpoint` configuration
- Added under a new `// MARK: - GraphQL Operations` section

## - [x] Phase 2: Add Image URL Resolution and Download to Service Layer

Create an image resolution and download service that:
1. Extracts image URLs from the raw body text
2. Matches them against resolved URLs from `bodyHTML`
3. Downloads images to a local directory

**Files modified:**
- `Sources/services/PRRadarCLIService/ImageDownloadService.swift` (new file)

**Tasks:**
- [x] Create `ImageDownloadService` struct with methods:
  - [x] `resolveImageURLs(body:bodyHTML:) -> [String: URL]` — Parses the raw body for `github.com/user-attachments/assets/` URLs, finds corresponding resolved URLs in `bodyHTML`, returns a mapping of `originalURL → resolvedSignedURL`
  - [x] `downloadImages(urls:[String: URL], to directory:String) async throws -> [String: String]` — Downloads each image from its signed URL, saves with a deterministic filename (the UUID from the original URL + detected extension), returns mapping of `originalURL → localFilename`
  - [x] `rewriteBody(_:urlMap:[String: String], baseDir:String) -> String` — Replaces original URLs in the body text with local file paths

**Architecture note (Services layer):** This coordinates multiple operations (parse, download, rewrite) using SDK-level primitives. It's a shared stateless utility, not multi-step orchestration, so Services is the correct layer.

**Technical notes:**
- `Sendable` struct with injectable `URLSession` (defaults to `.shared`)
- URL matching uses UUID extraction: original URLs contain a UUID in `github.com/user-attachments/assets/<UUID>`, and the resolved `bodyHTML` img src URLs also contain the same UUID — this is used to correlate them
- File extension detection uses MIME type from the HTTP response with magic byte fallback (PNG, JPEG, GIF, WebP)
- Download failures are silently skipped (non-fatal) — the original URL stays in place, matching the graceful degradation requirement
- Regex-based extraction: `NSRegularExpression` for both markdown body URL parsing and HTML `<img src>` parsing

## - [ ] Phase 3: Integrate Image Download into PR Acquisition

Wire the image download into `PRAcquisitionService` so images are fetched and stored during the pull-request acquisition phase.

**Files to modify:**
- `Sources/services/PRRadarCLIService/PRAcquisitionService.swift`
- `Sources/services/PRRadarCLIService/GitHubService.swift`

**Tasks:**
- In `GitHubService`, add a method to fetch `bodyHTML` for a PR (delegates to `OctokitClient.pullRequestBodyHTML`)
- In `PRAcquisitionService.acquire()`, after writing `gh-pr.json`:
  1. Fetch `bodyHTML` via `GitHubService`
  2. Call `ImageDownloadService.resolveImageURLs()` for the PR body
  3. Do the same for each comment body in `gh-comments.json` (comments can also have images)
  4. Download all resolved images to an `images/` subdirectory inside the phase directory (e.g., `code-reviews/1/phase-1-pull-request/images/`)
  5. Write a `image-url-map.json` file mapping original URLs to local filenames

**Output structure:**
```
phase-1-pull-request/
├── gh-pr.json
├── gh-comments.json
├── images/
│   ├── c58bb437-7807-4182-aec3-fff61f007aa7.png
│   └── ...
└── image-url-map.json   # {"https://github.com/user-attachments/assets/UUID": "c58bb437-...png"}
```

**Error handling:** Image download failures should be logged but not block acquisition. Missing images degrade gracefully (the original URL stays, same as current behavior).

## - [ ] Phase 4: Update RichContentView to Use Local Images

Modify `RichContentView` to rewrite image URLs to local file paths before rendering.

**Files to modify:**
- `Sources/apps/MacApp/UI/RichContentView.swift`
- `Sources/apps/MacApp/UI/PhaseViews/SummaryPhaseView.swift`
- `Sources/apps/MacApp/UI/GitViews/InlinePostedCommentView.swift`

**Tasks:**
- Add an optional `imageBaseDir: String?` parameter to `RichContentView`
- Add an optional `imageURLMap: [String: String]?` parameter to `RichContentView`
- When both are provided, before parsing content into segments, replace all mapped URLs with `file://{imageBaseDir}/{localFilename}` paths
- In `HTMLBlockView`, when a `baseURL` is set (for local images), pass it to `loadHTMLString(_:baseURL:)` — OR rewrite the `src` attributes directly in the HTML string before loading
- Update `SummaryPhaseView` and `InlinePostedCommentView` to load `image-url-map.json` and pass the image directory path and URL map to `RichContentView`

**Architecture note (Apps layer):** The view is responsible for I/O (loading the map file, constructing file paths). This is correct per the architecture — Apps handle I/O and platform concerns.

## - [ ] Phase 5: Architecture Validation

Review all commits made during the preceding phases and validate they follow the project's architectural conventions.

**For Swift changes** (`pr-radar-mac/`):
- Re-read the `swift-architecture` and `swift-swiftui` skills from `https://github.com/gestrich/swift-app-architecture` (`plugin/skills/`)
- Compare the commits made against the conventions described in each skill
- If any code violates the conventions, make corrections

**Process:**
1. Run `git log` to identify all commits made during this plan's execution
2. Run `git diff` against the starting commit to see all changes
3. Fetch and read ALL skills from the architecture repo
4. Evaluate the changes against each skill's conventions
5. Fix any violations found

**Key checks:**
- SDK method is stateless and Sendable
- Service doesn't import App-layer types
- No @Observable outside the Apps layer
- `ImageDownloadService` follows existing service patterns (struct, async methods)

## - [ ] Phase 6: Validation

**Automated testing:**
- `swift build` — Ensure the project compiles
- `swift test` — Ensure existing tests pass

**Manual verification:**
- Run `swift run PRRadarMacCLI diff 1 --config test-repo` to trigger acquisition with image download
- Check that `images/` directory and `image-url-map.json` are created in the phase output
- Launch `swift run MacApp`, navigate to a PR with images, confirm images render in the summary view

**Success criteria:**
- Images from `github.com/user-attachments/assets/` URLs display correctly in the Mac app
- No regressions in existing tests
- Image download failures don't block PR acquisition
