* Create Xcode Project
    * Will avoid constant Desktop folder prompts
    * Will support custom icon
    * Will support docs in xcode organizer
* Use Docc for docs so they show in xcode
* Restart State
    * Ensure state loads automatically on restart
    * Seems like it does not at least not for analyze phase - see pr 18702
    * Make sure loads for all phases without needing to refresh on restart
* Analyze All
    * Check it loads views live
    * Get feedback when analyzing all
        * Output
        * Count complete.. i.e. 1/100
* UI
    * On rules view, the task counts are confusing
    * Button to open PR folder in Finder
    * Check what refresh button does
    * In comment view, diff is too narrow
    * Button to open Pull request on web
    * Add PR author info
* Its not clear what happens when there are no tasks to run
    * i.e. what do subsequent states show?
* Effective diff
    * Verify working
    * Fix views
    * Ensure moved files work ok with nullability/imports
* Local Triage Runs
    * Get easily readable daily report
    * Total cost
    * Run on cron daily
* CI Runs
    * May need shallow commit + Github diff?
