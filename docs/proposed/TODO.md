# TODO

## Small


- [ ] Combine rules info in diff view
  The rules phase can be merged into the diff view. We can do this with a buton above each file in diff view that show that tasks that were run on it. That would show al lthe details (rule info, and results)
- [ ] Persist AI output as artifacts and support viewing in app/CLI
  AI output from each pipeline step should be saved to a file alongside the other
  artifacts. When browsing results in the MacApp or CLI, the AI output from the run
  should be visible. The UI should also support streaming output during a live run
  (both real-time while running and after completion).
- [ ] Create Xcode project
  Avoids constant Desktop folder prompts, supports custom icon, and supports
  docs in the Xcode organizer.
- [ ] Show moved/renamed files in diff view
  Moved or renamed files are not currently displayed in the diff. They should be
  shown. Example PR with moved files: https://github.com/jeppesen-foreflight/ff-ios/pull/18730/changes
- [ ] Show GitHub real name in UI alongside handle
  Display the user's full name (from GitHub profile) in addition to their handle
  where author info is shown, if available via the GitHub API.
- [ ] Posted comments badge indicators
  Show a badge on each PR in the list view indicating the number of posted
  (not pending) comments, styled with a different color than pending comments.
  Also show a per-file badge in the file list indicating how many posted
  comments exist for that file.
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

## Medium

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
- [ ] Audit PullRequests app for reusable ideas
  Audit `/Users/bill/Developer/work/swift/PullRequests` for features and patterns
  worth adopting in PRRadar. Likely candidates: better UI patterns (possible
  markdown rendering support), optimized fetching strategies that avoid
  over-fetching data, and any other polished UX or architecture ideas. Document
  findings and create follow-up TODO items for anything worth extracting.

## Large

- [ ] CI runs
  May need shallow commit + GitHub diff approach.
