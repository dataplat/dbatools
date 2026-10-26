# The only thing that reconciles. Serialization comes from three settings that have to
# stay together: maximumInstanceCount 1 on the app, and batchSize 1 with
# newBatchThreshold 0 in host.json. That triple is what the runner-fleet concurrency
# group used to do in GitHub Actions.
#
# The queue message is a hint about why we woke up. Invoke-FleetReconcile re-reads the
# whole GitHub queue and the whole Azure inventory regardless, and corroborates the
# actor/sha/ref against GitHub before any of it reaches a decision, so a wrong, stale or
# replayed hint costs one converge pass and changes nothing.

param($QueueItem, $TriggerMetadata)

$nudge = $QueueItem
if ($nudge -is [string]) {
    $nudge = $nudge | ConvertFrom-Json -Depth 6
}
$reason = [string]$nudge.reason
Write-Host "reconcile reason=$reason delivery=$($nudge.delivery) attempt=$($TriggerMetadata.DequeueCount)"

# A nudge that sat in the queue past STALE_NUDGE_MINUTES is dropped here. The pass it
# would trigger re-reads everything and learns nothing a fresher message will not also
# learn, and during a backlog those redundant passes are the backlog. Missing or
# unreadable insertion times count as fresh -- explicitly, not by trusting a cast to
# fail -- because the failure mode of dropping too eagerly is a cold fleet, and the
# failure mode of processing is one wasted pass.
$ageMinutes = 0
$insertedOn = $TriggerMetadata.InsertionTime
if ($null -eq $insertedOn) {
    Write-Warning "The trigger metadata carries no InsertionTime; treating the nudge as fresh."
} else {
    try {
        if ($insertedOn -is [string]) {
            $insertedOn = [DateTimeOffset]::Parse($insertedOn, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        $ageMinutes = ([DateTimeOffset]::UtcNow - [DateTimeOffset]$insertedOn).TotalMinutes
    } catch {
        Write-Warning "Could not read the nudge insertion time; treating it as fresh. $($PSItem.Exception.Message)"
    }
}
$staleMinutes = [int](Get-FleetConfig)["STALE_NUDGE_MINUTES"]
if ($staleMinutes -gt 0 -and $ageMinutes -ge $staleMinutes) {
    Write-Host "dropped stale nudge reason=$reason delivery=$($nudge.delivery) age_minutes=$([math]::Floor($ageMinutes))"
    return
}

$splatReconcile = @{
    DirectTriggerActor   = [string]$nudge.actor
    DirectTriggerMessage = [string]$nudge.message
    DirectTriggerSha     = [string]$nudge.sha
    DirectTriggerRef     = [string]$nudge.ref
}
Invoke-FleetReconcile @splatReconcile
