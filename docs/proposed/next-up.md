* Ensure loads automatically on restart
    * Seems like it does not at least not for analyze phase - see pr 18702
    * Make sure loads for all phases withotu needing to refresh on restart
    * It's not clear what the refresh button does as its not refreshing
* On rules view, the task counts are confusing
* Its not clear what happens when there are no tasks to run
    * i.e. what do subsequent states show?
* Ensure loads live when doing analyze all (for multiple PRs)
* Get feedback when analyzing all
    * Output
    * Count complete.. i.e. 1/100
* Effective diff
    * Verify working
    * Fix views
* Ensure moved files work ok with nullability/imports
* Get easily readable daily report
* Run on cron daily
    * Total cost
* CI Runs
    * May need shallow commit + Github diff?