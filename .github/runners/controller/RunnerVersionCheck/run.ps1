# Daily at 06:00 UTC. GitHub gives a runner version some weeks between publishing the
# date it retires and enforcing it, and the check costs three GitHub API reads, so a daily
# look leaves the most time to act. See Invoke-RunnerVersionCheck in FleetCore.

param($Timer)

Invoke-RunnerVersionCheck
