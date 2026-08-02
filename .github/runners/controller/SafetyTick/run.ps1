# The missed-webhook net, on the same five-minute cadence the cron reconcile used.
# GitHub does not redeliver a webhook that failed, so without this a single dropped
# delivery could leave a lane cold until the next unrelated event.
#
# It enqueues rather than reconciling inline: everything that reconciles has to go
# through the one queue, or a tick and a nudge could run at the same time inside the
# single instance.

param($Timer)

if ($Timer.IsPastDue) {
    Write-Warning "Safety tick is running late; the host was likely idle or restarting."
}
Push-OutputBinding -Name Nudge -Value (@{ reason = "safety-tick" } | ConvertTo-Json -Compress)
