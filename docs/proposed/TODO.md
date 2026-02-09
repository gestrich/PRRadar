# TODO

## Small

- [ ] Add button to open pull request on web
- [ ] Add PR author info to the UI
- [ ] Fix comment view diff width
  In the comment view, the diff column is too narrow.
- [ ] Fix task counts display on rules view
  The task counts shown are confusing.
- [ ] Check what refresh button does
  Audit the refresh button behavior and fix or document it.
- [ ] Clarify behavior when there are no tasks to run
  What do subsequent pipeline states show when there are nothing to evaluate?
- [ ] Filter tasks/rules list by selected file
  The rules phase view shows tasks but not filtered to the selected file.
  Should show file-specific tasks expandable with rule description and focus
  area details.
- [ ] Persist AI output as artifacts and support viewing in app/CLI
  AI output from each pipeline step should be saved to a file alongside the other
  artifacts. When browsing results in the MacApp or CLI, the AI output from the run
  should be visible. The UI should also support streaming output during a live run
  (both real-time while running and after completion).

## Medium

- [ ] Use DocC for documentation
  Add DocC so docs show in the Xcode organizer.
- [ ] Effective diff fixes
  Verify effective diff is working. Fix views. Ensure moved files work
  correctly with nullability/imports.
- [ ] Restart state handling
  Ensure state loads automatically on restart for all phases without needing
  to refresh. Currently broken for at least the analyze phase (see PR 18702).
- [ ] Analyze All improvements
  Verify views load live during batch analysis. Add feedback: output streaming
  and progress count (e.g. 1/100 complete).
- [ ] Per-task evaluation with play button
  Add a play button next to each task in the rules view to evaluate that
  specific task individually. Show a checkmark after evaluation completes.
  Requires a new `runSingleTask()` method in PRModel.
- [ ] Local triage runs
  Get an easily readable daily report with total cost. Run on cron daily.
- [ ] Unified file-centric review view
  Consolidate the diff, focus areas, rules, tasks, evaluations, and report
  phase views into a single file-centric view. Selecting a file shows the diff
  on top with rules/tasks listed underneath, scoped to that file. Analysis
  results (comments, evaluations) appear inline within the diff. This collapses
  the separate phase concepts into one cohesive view per file.
- [ ] Skip already-analyzed tasks during evaluation
  The analysis pipeline should detect when a specific rule/task has already been
  evaluated and skip re-running it. Still check whether the task was previously
  analyzed, but avoid re-invoking the AI if it was. This saves AI costs by not
  re-evaluating unchanged work across repeated runs.

## Large

- [ ] CI runs
  May need shallow commit + GitHub diff approach.
- [ ] Create Xcode project
  Avoids constant Desktop folder prompts, supports custom icon, and supports
  docs in the Xcode organizer.
