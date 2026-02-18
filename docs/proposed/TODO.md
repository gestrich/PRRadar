# TODO

## Small

- [ ] Clean phase output directories before each pipeline run
  The pipeline doesn't delete existing phase output files before writing new
  results. When a run produces 0 artifacts for a phase (e.g., 0 tasks), stale
  files from prior runs survive on disk and get picked up by downstream phases.
  This was the root cause of the "stale line numbers" bug — the evaluation phase
  read old task files containing outdated hunk content. Each phase should clear
  its output directory before writing, or the `analyze` command should wipe the
  entire PR output directory at the start.
- [ ] Fix focus_type mismatch: method-typed rules produce 0 tasks
  `FetchRulesUseCase` hardcodes `requestedTypes: [.file]`, so the pipeline only
  generates file-level focus areas. Rules with `focus_type: method` are silently
  filtered out by `TaskCreatorService`'s guard (`rule.focusType == focusArea.focusType`),
  producing 0 tasks. Options: (1) add `.method` to `requestedTypes` (extra AI
  call per hunk), (2) let file-level focus areas satisfy method rules (a file
  hunk contains all methods), or (3) default rules to `focus_type: file`.

- [ ] Persist AI output as artifacts and support viewing in app/CLI
  AI output from each pipeline step should be saved to a file alongside the other
  artifacts. When browsing results in the MacApp or CLI, the AI output from the run
  should be visible. The UI should also support streaming output during a live run
  (both real-time while running and after completion).
- [ ] Fix broken rule links in posted PR comments
  The links to the associated rule in posted comments are broken. May be caused
  by using a custom output folder on the Desktop. Needs investigation to confirm
  root cause and fix the URL/path generation.
- [ ] Auto-fetch PR data when opening a PR
  When a PR is selected in the Mac app, automatically fetch the latest diff,
  comments, and metadata (phase 1 / DIFF phase). Currently this requires a
  manual action. The data should start downloading as soon as the PR is opened
  so the user sees up-to-date information immediately.
- [ ] GitHub-style continuous scroll diff view
  Replace the current file-by-file diff navigation with a single continuous
  scrolling list showing all files in one view, similar to GitHub's PR diff
  page. The file list sidebar should act as scroll anchors — tapping a file
  name scrolls to that file's section within the unified scroll view.
- [ ] Auto-select first PR on launch
  When the PR list loads, automatically select the first PR so the user
  immediately sees PR details without needing to click.
- [ ] Auto-fetch PR list on launch
  When the main view opens, automatically fetch the latest PRs for the list
  so the user always sees up-to-date data without a manual refresh.
- [ ] Make SettingsService own persistence instead of requiring separate save calls
  SettingsService is anemic — clients must call a separate save after every
  mutation (add config, remove config, set default). Instead, each operation
  should persist internally so callers don't need to manage save timing. This
  also lets AppSettings drop `inout` usage and mutable vars since the service
  owns the read-modify-write cycle.
- [x] Make rules directory required or fall back to a well-known repo path
  Falls back to `{repoPath}/code-review-rules/` when rulesDir is not configured.
- [ ] Reorganize PRRadarCLIService into meaningful service modules
  The services in PRRadarCLIService apply to both the Mac app and CLI, not
  just the CLI. Break them out of the "CLIService" folder into more
  appropriately named service modules per the 4-layer architecture.
- [ ] Move GitDiffModels to a Git SDK
  GitDiffModels are general-purpose git diff types, not PRRadar-specific.
  Extract them into a dedicated Git SDK package in the SDKs layer so they
  can be reused independently.
- [ ] Compact comment status indicators in file list view
  After a pending comment is posted, the file list only shows a green indicator
  (meaning a comment exists on the file), but there's no way to distinguish
  PRRadar-posted comments from unrelated user comments. Need a compact visual
  system that shows: (1) how many total comments are on a file, (2) which are
  pending vs submitted, and (3) which were posted by our tool. Orange should
  indicate pending PRRadar comments; green alone is ambiguous.

## Medium

- [ ] Skip already-analyzed tasks during evaluation
  The analysis pipeline should detect when a specific rule/task has already been
  evaluated and skip re-running it. Still check whether the task was previously
  analyzed, but avoid re-invoking the AI if it was. This should also work at the
  file level: track which commit hash per file was last analyzed, and skip files
  whose diff hasn't changed since the last run. Requires persisting per-file
  analysis metadata (commit SHA, timestamp) so the pipeline can make smart
  decisions on subsequent runs. Saves AI costs by not re-evaluating unchanged
  work across repeated runs.
- [ ] Skip posting duplicate comments already on the PR
  The comment command should check existing posted comments on the PR before
  posting. If a pending comment matches one already posted (same file, line, and
  content), skip it instead of posting a duplicate. The pipeline already fetches
  PR comments, so the data is available — just needs a comparison step before
  posting.
- [ ] AI validation step to distinguish regressions from existing code
  Evaluations need to better determine whether a finding is a regression
  introduced by the PR author or pre-existing code that's only tangentially
  related. Add a validation step (possibly AI-powered) that checks whether a
  flagged issue is directly caused by the dev's changes or was already present.
  This would reduce false positives and make reviews more actionable.
- [ ] Effective diff fixes
  Verify effective diff is working. Fix views. Ensure moved files work
  correctly with nullability/imports.
- [ ] Per-task and per-rule evaluation with play button
  Add a play button next to each task in the rules view to evaluate that specific
  task individually. Show a checkmark after evaluation completes. Requires a new
  `runSingleTask()` method in PRModel. Also support running a single rule from
  the "analyze all" flow — when a PR is open, run just one selected rule across
  all files. If a specific file is open, scope the analysis to just that file.
  Enables faster iteration without re-running the full pipeline.
- [ ] Local triage runs
  Get an easily readable daily report with total cost. Run on cron daily.
- [ ] Single diff view with inline analysis
  Currently the diff is duplicated across the diff view and the analyze view.
  Combine these into a single diff view that gets decorated with analysis data
  after evaluation completes. Pending comments can be added inline once analysis
  is done. Keep the rules view as-is.
- [ ] Add reviewer details (who is reviewing and approval status)
  Show which GitHub users are assigned as reviewers on each PR and their
  current review status (pending, approved, changes requested). Display
  this in both the PR list and detail views so the user can quickly see
  review progress at a glance.
- [ ] Investigate misclassified "General Comments" in file view
  In the file view, some comments categorized as "General Comments" don't appear
  to actually be general (observed in PR 18743). Needs research to determine why
  non-general comments are ending up in the general section — could be a
  classification issue in the evaluation pipeline or a filtering/grouping bug in
  the UI layer.
- [ ] Add principles from GoldenPath to swift-app-architecture
  Review the principles in `/Users/bill/Developer/personal/GoldenPath` and
  incorporate relevant ones into `/Users/bill/Developer/personal/swift-app-architecture/`.
  This ensures the architecture reference repo reflects the broader coding
  principles and conventions captured in GoldenPath.
- [ ] Audit PullRequests app for reusable ideas
  Audit `/Users/bill/Developer/work/swift/PullRequests` for features and patterns
  worth adopting in PRRadar. Likely candidates: better UI patterns (possible
  markdown rendering support), optimized fetching strategies that avoid
  over-fetching data, and any other polished UX or architecture ideas. Document
  findings and create follow-up TODO items for anything worth extracting.

## Large

- [ ] CI runs
  May need shallow commit + GitHub diff approach.
