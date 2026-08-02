# The only thing that reconciles. Serialization comes from three settings that have to
# stay together: maximumInstanceCount 1 on the app, and batchSize 1 with
# newBatchThreshold 0 in host.json. That triple is what the runner-fleet concurrency
# group used to do in GitHub Actions.
#
# The queue message is a hint about why we woke up. Invoke-FleetReconcile re-reads the
# whole GitHub queue and the whole Azure inventory regardless, so a wrong or forged hint
# costs one converge pass and changes no decision.

param($QueueItem, $TriggerMetadata)

$nudge = $QueueItem
if ($nudge -is [string]) {
    $nudge = $nudge | ConvertFrom-Json -Depth 6
}
$reason = [string]$nudge.reason
Write-Host "reconcile reason=$reason delivery=$($nudge.delivery) attempt=$($TriggerMetadata.DequeueCount)"

$splatReconcile = @{
    DirectTriggerActor   = [string]$nudge.actor
    DirectTriggerMessage = [string]$nudge.message
    DirectTriggerSha     = [string]$nudge.sha
    DirectTriggerRef     = [string]$nudge.ref
}
Invoke-FleetReconcile @splatReconcile
