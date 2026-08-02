function Test-CiMarker {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message,
        [Parameter(Mandatory)]
        [string]$Marker
    )

    -1 -ne ([string]$Message).IndexOf($Marker, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-PushHeadMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ActivityEvent
    )

    $head = [string]$ActivityEvent.payload.head
    $commits = @($ActivityEvent.payload.commits)
    $headCommit = @($commits | Where-Object { [string]$PSItem.sha -eq $head } | Select-Object -First 1)
    if ($headCommit) {
        return [string]$headCommit[0].message
    }
    if ($ActivityEvent.payload.head_commit) {
        return [string]$ActivityEvent.payload.head_commit.message
    }
    if ($commits) {
        return [string]$commits[-1].message
    }
    return ""
}

function Get-CiRunMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Run
    )

    $messages = @()
    if ($Run.head_commit) {
        $messages += [string]$Run.head_commit.message
    }
    if ($Run.display_title) {
        $messages += [string]$Run.display_title
    }
    return $messages -join " "
}

function Get-CiRunActor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Run
    )

    if ([string]$Run.display_title -match "\[pool:([^\]]+)\]") {
        return [string]$Matches[1]
    }
    return [string]$Run.actor.login
}

function Test-CiRunEligible {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Run,
        [Parameter(Mandatory)]
        [string[]]$OptInPushUsers,
        [Parameter(Mandatory)]
        [string]$Marker
    )

    $actor = Get-CiRunActor -Run $Run
    if ($actor -notin $OptInPushUsers) {
        return $true
    }
    if ([string]$Run.event -eq "pull_request") {
        return $true
    }
    $message = Get-CiRunMessage -Run $Run
    return Test-CiMarker -Message $message -Marker $Marker
}

function Test-MaintainerActivityEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ActivityEvent,
        [Parameter(Mandatory)]
        [string]$Maintainer,
        [Parameter(Mandatory)]
        [string[]]$OptInPushUsers,
        [Parameter(Mandatory)]
        [string]$Marker,
        [Parameter(Mandatory)]
        [DateTimeOffset]$Cutoff
    )

    if ([string]$ActivityEvent.actor.login -ne $Maintainer) {
        return $false
    }
    if ([DateTimeOffset]::Parse([string]$ActivityEvent.created_at) -le $Cutoff) {
        return $false
    }
    if ([string]$ActivityEvent.type -eq "PullRequestEvent") {
        return [string]$ActivityEvent.payload.action -in @("opened", "reopened", "synchronize")
    }
    if ([string]$ActivityEvent.type -ne "PushEvent") {
        return $false
    }
    if ($Maintainer -notin $OptInPushUsers) {
        return $true
    }
    $message = Get-PushHeadMessage -ActivityEvent $ActivityEvent
    return Test-CiMarker -Message $message -Marker $Marker
}

function Get-PoolJobDemandFromJobs {
    param(
        [object[]]$Jobs = @(),
        [string]$PoolLabelPrefix = "dbatools-pool-"
    )
    # Demand is read from each job's own dbatools-pool-* label rather than from the
    # run's actor. That is exact: it counts only jobs that actually queue against this
    # fleet (ci-azure.yml's authorize job runs on ubuntu-latest and carries no pool
    # label), and it already honours the [pool:...] display-title override, because
    # the workflow resolved inputs.pool_user into runs-on before the job was created.
    #
    # Anything not "completed" needs a runner, so the filter is negative rather than a
    # whitelist -- GitHub has added job statuses (waiting, pending, requested) since
    # this fleet was written and will add more.
    $demand = @{ }
    foreach ($job in $Jobs) {
        if ([string]$job.status -eq "completed") {
            continue
        }
        $poolLabel = @($job.labels | Where-Object { $PSItem -like "$PoolLabelPrefix*" } | Select-Object -First 1)
        if (-not $poolLabel) {
            continue
        }
        $pool = ([string]$poolLabel[0]).Substring($PoolLabelPrefix.Length)
        if (-not $demand.ContainsKey($pool)) {
            $demand[$pool] = 0
        }
        $demand[$pool] += 1
    }
    $demand
}

function Get-PoolJobDemandFromRuns {
    [CmdletBinding()]
    param(
        [object[]]$WorkflowRuns = @(),
        [hashtable]$JobsByRun = @{ },
        [Parameter(Mandatory)]
        [string[]]$Maintainers,
        [Parameter(Mandatory)]
        [string[]]$OptInPushUsers,
        [Parameter(Mandatory)]
        [string]$Marker,
        [Parameter(Mandatory)]
        [int]$MaintainerCount,
        [Parameter(Mandatory)]
        [int]$CommunityCount,
        [string]$PoolLabelPrefix = "dbatools-pool-"
    )

    $demand = @{ }
    $eligibleLiveRuns = @($WorkflowRuns | Where-Object {
            $splatEligibility = @{
                Run            = $PSItem
                OptInPushUsers = $OptInPushUsers
                Marker         = $Marker
            }
            [string]$PSItem.status -ne "completed" -and (Test-CiRunEligible @splatEligibility)
        })
    foreach ($run in $eligibleLiveRuns) {
        $runId = [string]$run.id
        $jobs = @()
        if ($JobsByRun.ContainsKey($runId)) {
            $jobs = @($JobsByRun[$runId])
        }
        $fleetJobs = @($jobs | Where-Object {
                @($PSItem.labels | Where-Object { $PSItem -like "$PoolLabelPrefix*" }).Count -gt 0
            })
        if (-not $fleetJobs) {
            # The authorization job exists before the fleet matrix. Estimate one full
            # pool for that short gap; once any fleet-labelled job exists, even a
            # completed one, the real pending count replaces the estimate.
            $pool = Get-CiRunActor -Run $run
            $poolSize = $MaintainerCount
            if ($pool -notin $Maintainers) {
                $pool = "community"
                $poolSize = $CommunityCount
            }
            if (-not $demand.ContainsKey($pool) -or $demand[$pool] -lt $poolSize) {
                $demand[$pool] = $poolSize
            }
            continue
        }

        $runDemand = Get-PoolJobDemandFromJobs -Jobs $fleetJobs -PoolLabelPrefix $PoolLabelPrefix
        foreach ($pool in $runDemand.Keys) {
            if (-not $demand.ContainsKey($pool)) {
                $demand[$pool] = 0
            }
            $demand[$pool] += $runDemand[$pool]
        }
    }
    $demand
}

function Get-VmssCapacityPlan {
    [CmdletBinding()]
    param(
        [ValidateRange(0, 35)]
        [int]$NominalCapacity,
        [ValidateRange(0, 35)]
        [int]$ActualCapacity,
        [ValidateRange(0, 35)]
        [int]$TargetCapacity
    )

    if ($NominalCapacity -gt $ActualCapacity) {
        $ActualCapacity
    }
    if ($ActualCapacity -lt $TargetCapacity) {
        $TargetCapacity
    }
}

function Get-DesiredRunnerPools {
    [CmdletBinding()]
    param(
        [object[]]$Events = @(),
        [object[]]$WorkflowRuns = @(),
        [Parameter(Mandatory)]
        [string[]]$Maintainers,
        [Parameter(Mandatory)]
        [string[]]$OptInPushUsers,
        [Parameter(Mandatory)]
        [int]$MaintainerCount,
        [Parameter(Mandatory)]
        [int]$MaintainerWindowMinutes,
        [Parameter(Mandatory)]
        [int]$CommunityCount,
        [Parameter(Mandatory)]
        [int]$CommunityGraceMinutes,
        [Parameter(Mandatory)]
        [int]$MaxRunners,
        [Parameter(Mandatory)]
        [string]$Marker,
        [Parameter(Mandatory)]
        [DateTimeOffset]$Now,
        [AllowEmptyString()]
        [string]$DirectTriggerActor = "",
        [AllowEmptyString()]
        [string]$DirectTriggerMessage = "",
        [hashtable]$PoolJobDemand = @{ },
        [ValidateRange(0, 35)]
        [int]$WarmFloor = 0
    )

    $maintainerCutoff = $Now.AddMinutes(-$MaintainerWindowMinutes)
    $communityCutoff = $Now.AddMinutes(-$CommunityGraceMinutes)
    $eligibleRuns = @($WorkflowRuns | Where-Object {
            Test-CiRunEligible -Run $PSItem -OptInPushUsers $OptInPushUsers -Marker $Marker
        })
    $liveRuns = @($eligibleRuns | Where-Object { [string]$PSItem.status -ne "completed" })
    $desired = [ordered]@{}

    foreach ($maintainer in $Maintainers) {
        $recentActivity = @($Events | Where-Object {
                Test-MaintainerActivityEvent -ActivityEvent $PSItem -Maintainer $maintainer -OptInPushUsers $OptInPushUsers -Marker $Marker -Cutoff $maintainerCutoff
            }).Count -gt 0
        $liveCi = @($liveRuns | Where-Object { (Get-CiRunActor -Run $PSItem) -eq $maintainer }).Count -gt 0
        $recentlyCompletedCi = @($eligibleRuns | Where-Object {
                (Get-CiRunActor -Run $PSItem) -eq $maintainer -and
                [string]$PSItem.status -eq "completed" -and
                [DateTimeOffset]::Parse([string]$PSItem.updated_at) -gt $maintainerCutoff
            }).Count -gt 0
        $directTrigger = $DirectTriggerActor -eq $maintainer
        if ($directTrigger -and $maintainer -in $OptInPushUsers) {
            $directTrigger = Test-CiMarker -Message $DirectTriggerMessage -Marker $Marker
        }
        $hot = $recentActivity -or $liveCi -or $recentlyCompletedCi -or $directTrigger
        $desired[$maintainer] = if ($hot) { $MaintainerCount } else { 0 }
    }

    $communityLive = @($liveRuns | Where-Object {
            (Get-CiRunActor -Run $PSItem) -notin $Maintainers
        }).Count -gt 0
    $communityRecentlyCompleted = @($eligibleRuns | Where-Object {
            (Get-CiRunActor -Run $PSItem) -notin $Maintainers -and
            [string]$PSItem.status -eq "completed" -and
            [DateTimeOffset]::Parse([string]$PSItem.updated_at) -gt $communityCutoff
        }).Count -gt 0
    $directCommunityTrigger = $DirectTriggerActor -and $DirectTriggerActor -notin $Maintainers
    $communityHot = $communityLive -or $communityRecentlyCompleted -or $directCommunityTrigger
    $communityPending = 0
    if ($PoolJobDemand.ContainsKey("community")) {
        $communityPending = [int]$PoolJobDemand["community"]
    }
    $desired["community"] = if (-not $communityHot) {
        0
    } elseif ($communityPending -gt 0) {
        [math]::Min($CommunityCount, $communityPending)
    } else {
        [math]::Min($CommunityCount, $WarmFloor)
    }

    $total = ($desired.Values | Measure-Object -Sum).Sum
    if ($total -gt $MaxRunners) {
        throw "Pool policy requests $total runners but MAX_RUNNERS is $MaxRunners"
    }
    return $desired
}

function Get-MarkedPushDispatch {
    [CmdletBinding()]
    param(
        [object[]]$Events = @(),
        [object[]]$WorkflowRuns = @(),
        [Parameter(Mandatory)]
        [string[]]$OptInPushUsers,
        [Parameter(Mandatory)]
        [string]$Marker,
        [Parameter(Mandatory)]
        [DateTimeOffset]$Cutoff,
        [AllowEmptyString()]
        [string]$DirectTriggerActor = "",
        [AllowEmptyString()]
        [string]$DirectTriggerMessage = "",
        [AllowEmptyString()]
        [string]$DirectTriggerSha = "",
        [AllowEmptyString()]
        [string]$DirectTriggerRef = ""
    )

    $candidates = @()
    if ($DirectTriggerActor -in $OptInPushUsers -and
        $DirectTriggerSha -and
        $DirectTriggerRef -and
        (Test-CiMarker -Message $DirectTriggerMessage -Marker $Marker)) {
        $candidates += [pscustomobject]@{
            Actor     = $DirectTriggerActor
            Ref       = $DirectTriggerRef -replace "^refs/heads/", ""
            Sha       = $DirectTriggerSha
            Message   = $DirectTriggerMessage
            CreatedAt = [DateTimeOffset]::UtcNow
        }
    }

    foreach ($activityEvent in $Events) {
        if ([string]$activityEvent.type -ne "PushEvent" -or
            [string]$activityEvent.actor.login -notin $OptInPushUsers -or
            [DateTimeOffset]::Parse([string]$activityEvent.created_at) -le $Cutoff) {
            continue
        }
        $message = Get-PushHeadMessage -ActivityEvent $activityEvent
        if (-not (Test-CiMarker -Message $message -Marker $Marker)) {
            continue
        }
        $candidates += [pscustomobject]@{
            Actor     = [string]$activityEvent.actor.login
            Ref       = ([string]$activityEvent.payload.ref) -replace "^refs/heads/", ""
            Sha       = [string]$activityEvent.payload.head
            Message   = $message
            CreatedAt = [DateTimeOffset]::Parse([string]$activityEvent.created_at)
        }
    }

    foreach ($candidate in @($candidates | Sort-Object CreatedAt -Descending)) {
        $existing = @($WorkflowRuns | Where-Object {
                [string]$PSItem.head_sha -eq $candidate.Sha
            }).Count -gt 0
        if (-not $existing) {
            return $candidate
        }
    }
    return $null
}
