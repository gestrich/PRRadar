# TODO

## Small

- [ ] Fix task counts display on rules view
  The task counts shown are confusing.
- [ ] Filter tasks/rules list by selected file
  The rules phase view shows tasks but not filtered to the selected file.
  Should show file-specific tasks expandable with rule description and focus
  area details.
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
- [ ] Show all GitHub comment details in Mac app comment preview
  The comment preview in the Mac diff view is missing details that appear in the
  posted GitHub comments — specifically the "PR Radar" link and the cost to run.
  Ensure all metadata shown in the GitHub comment is also displayed in the app's
  comment preview.
- [ ] Show model used in report and cost displays
  Wherever we show cost (e.g., report output, comment preview, CLI summary), also
  display the AI model that was used for the evaluation. Helps with understanding
  cost differences and reproducing results.
- [ ] Hide PR-level comments from file view
  PR-level comments (not associated with a specific file) should not appear in the
  per-file comment view. Only file-level comments should be shown there.
- [ ] Posted comments badge indicators
  Show a badge on each PR in the list view indicating the number of posted
  (not pending) comments, styled with a different color than pending comments.
  Also show a per-file badge in the file list indicating how many posted
  comments exist for that file.
- [ ] Render pending comments as markdown using the same views as posted comments
  Pending comments should display using the exact markdown string that will be
  posted to the PR. This means reusing the same comment rendering views used for
  posted GitHub comments, giving a consistent look and a true preview of what
  will appear on the PR.
- [ ] Differentiate PR status in PR list view
  Show visual differences between PR states: merged vs closed (not merged), and
  open vs draft. Use distinct colors or icons so the status is immediately clear
  at a glance in the list view.

## Medium

- [ ] Effective diff fixes
  Verify effective diff is working. Fix views. Ensure moved files work
  correctly with nullability/imports.
- [ ] Per-task evaluation with play button
  Add a play button next to each task in the rules view to evaluate that specific task individually. Show a checkmark after evaluation completes.
  Requires a new `runSingleTask()` method in PRModel.
- [ ] Local triage runs
  Get an easily readable daily report with total cost. Run on cron daily.
- [ ] Single diff view with inline analysis
  Currently the diff is duplicated across the diff view and the analyze view.
  Combine these into a single diff view that gets decorated with analysis data
  after evaluation completes. Pending comments can be added inline once analysis
  is done. Keep the rules view as-is.
- [ ] Skip already-analyzed tasks during evaluation
  The analysis pipeline should detect when a specific rule/task has already been evaluated and skip re-running it. Still check whether the task was previously analyzed, but avoid re-invoking the AI if it was. This saves AI costs by not re-evaluating unchanged work across repeated runs.
- [ ] Audit PullRequests app for reusable ideas
  Audit `/Users/bill/Developer/work/swift/PullRequests` for features and patterns
  worth adopting in PRRadar. Likely candidates: better UI patterns (possible
  markdown rendering support), optimized fetching strategies that avoid
  over-fetching data, and any other polished UX or architecture ideas. Document
  findings and create follow-up TODO items for anything worth extracting.

## Large

- [ ] CI runs
  May need shallow commit + GitHub diff approach.
