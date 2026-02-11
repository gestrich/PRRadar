## Background

This plan covers the follow-on work after the unified `ReviewComment` model (see [unified-review-comment-model.md](unified-review-comment-model.md)). That first plan uses heuristic text matching (`body.contains(ruleName)`) to pair pending and posted comments. The heuristics work but are fragile — a rule name that happens to be a substring of another rule's comment body could cause false matches.

This plan addresses three areas:
1. **Hidden metadata** — embed structured identifiers in posted comments so matching is reliable, not heuristic
2. **Auto-commenting duplicate prevention** — reuse the matching logic in the posting pipeline so automated runs don't double-post
3. **GitHub API line number behavior** — investigate how GitHub handles comment line numbers when diffs shift, which affects all matching strategies

### Relevant existing infrastructure

- **HTML comment filtering** in `RichContentView` already skips `<!-- -->` blocks during rendering, so hidden metadata in HTML comments would be invisible in the MacApp UI
- **GitHub also hides HTML comments** in their rendered markdown, so `<!-- metadata -->` would be invisible on github.com too
- **`PRComment.toGitHubMarkdown()`** ([PRComment.swift](PRRadarLibrary/Sources/services/PRRadarModels/PRComment.swift)) generates the markdown posted to GitHub — this is where metadata would be appended
- **`CommentService`** ([CommentService.swift](PRRadarLibrary/Sources/services/PRRadarCLIService/CommentService.swift)) handles posting comments to GitHub
- **`PostCommentsUseCase`** ([PostCommentsUseCase.swift](PRRadarLibrary/Sources/features/PRReviewFeature/usecases/PostCommentsUseCase.swift)) orchestrates the comment posting flow

## Phases

## - [ ] Phase 1: Embed Hidden Metadata in Posted Comments

Replace heuristic text-matching with structured metadata embedded as an HTML comment in the posted GitHub markdown. Invisible both on github.com and in the MacApp (`RichContentView` already filters `<!-- -->`).

**Metadata format** (appended to `toGitHubMarkdown()` output):
```
<!-- prradar:rule=rule-name:commit=abc123:file=path/to/file.swift:line=42 -->
```

Fields:
- `rule` — rule identifier (e.g., `no-force-unwrap`)
- `commit` — the commit hash the analysis ran against
- `file` — file path the violation is in
- `line` — line number of the violation

**PRComment.swift:**
- Add `commitHash: String?` field to `PRComment`
- Populate from the diff's commit hash when creating `PRComment.from(evaluation:task:)`
- Update `toGitHubMarkdown()` to append the metadata HTML comment

**New: PRRadarCommentMetadata model** (in PRRadarModels):
- Struct with `ruleName`, `commitHash`, `filePath`, `lineNumber` fields
- `func toHTMLComment() -> String` — serializes to `<!-- prradar:... -->`
- `static func parse(from body: String) -> PRRadarCommentMetadata?` — extracts metadata from a comment body using regex

**DiffCommentMapper.swift:**
- Update matching logic to prefer metadata-based matching (parse metadata from posted comment body)
- Fall back to heuristic matching for older comments that lack metadata

## - [ ] Phase 2: Auto-Commenting Duplicate Prevention

When the tool runs automatically, it must not post duplicate comments for violations that were already commented on. Use the same matching logic from Phase 1 in the comment posting pipeline.

**CommentService.swift / PostCommentsUseCase.swift:**
- Before posting, fetch current posted comments for the PR
- For each pending comment, check if a matching posted comment exists (using metadata parsing from Phase 1, falling back to heuristics)
- Skip already-posted violations
- Log skipped duplicates for visibility

**Conceptual shift:** Think in terms of tasks — "for this task/violation, has a comment already been posted?" rather than pure text comparison. The metadata makes this reliable. Right now matching may use the comment text, but eventually it should use the structured metadata to answer the question definitively.

## - [ ] Phase 3: Investigation — GitHub API Line Number Behavior

Experimental phase to understand how GitHub handles comment line numbers when diffs change. This affects all matching strategies — if line numbers drift, metadata-based matching with a stored `line` field might not align with what GitHub returns.

**Questions to answer:**
- When a developer pushes new commits that shift lines, does the GitHub API return the original line number or the updated position?
- Does it differ for resolved vs. open comments?
- Does it differ for comments on outdated diffs vs. current diffs?
- What fields does the API return? (`line`, `original_line`, `position` — which is which?)

**Approach:**
- Use the test repo (`/Users/bill/Developer/personal/PRRadar-TestRepo`)
- Post a comment on a specific line via PRRadar
- Push a commit that adds lines above the commented line
- Fetch the comment via `gh api` and inspect the returned `line`, `original_line`, and `position` fields
- Repeat with a resolved comment

**Impact:** Results will inform whether the metadata `line` field or the GitHub-returned `line` should be used for matching in subsequent analyses. If GitHub always returns the original line, the metadata `line` is sufficient. If GitHub updates the line, we may need to match on other fields or adjust.

## - [ ] Phase 4: Validation

**Automated:**
```bash
cd pr-radar-mac
swift build
swift test
```

**Phase 1 validation:**
1. Post a new comment after metadata changes
2. Check the GitHub comment body contains the `<!-- prradar:... -->` metadata (via `gh api`)
3. Verify it's invisible in both GitHub web UI and the MacApp
4. Verify the `ReviewComment` matching in `DiffCommentMapper` uses metadata when present and falls back to heuristics for older comments

**Phase 2 validation:**
1. Run `swift run PRRadarMacCLI comment 1 --config test-repo` to post comments
2. Run the same command again
3. Verify the second run skips already-posted violations and logs that they were skipped

**Phase 3 validation:**
Document findings in a new file (e.g., `docs/investigations/github-line-number-behavior.md`) with the raw API responses and conclusions.
