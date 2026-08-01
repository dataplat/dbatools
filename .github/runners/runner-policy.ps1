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
        $directTrigger = $DirectTriggerActor -eq $maintainer
        if ($directTrigger -and $maintainer -in $OptInPushUsers) {
            $directTrigger = Test-CiMarker -Message $DirectTriggerMessage -Marker $Marker
        }
        # Demand sizes a hot lane; it never heats a cold one. A community PR must not
        # be able to size a maintainer lane by reporting jobs against it.
        $hot = $recentActivity -or $liveCi -or $directTrigger
        $pending = 0
        if ($PoolJobDemand.ContainsKey($maintainer)) {
            $pending = [int]$PoolJobDemand[$maintainer]
        }
        $desired[$maintainer] = if (-not $hot) {
            0
        } elseif ($pending -gt 0) {
            [math]::Min($MaintainerCount, $pending)
        } else {
            [math]::Min($MaintainerCount, $WarmFloor)
        }
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
