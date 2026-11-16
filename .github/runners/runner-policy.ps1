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
    # A push run is a merge: ci-azure.yml only fires on: push for development, and since
    # #10508 the workflow runs the full matrix for every merge, marker or not. Requiring
    # the marker here starved merge runs of runners while their jobs sat queued. The
    # exemption is deliberately run-scoped: a push filtered out by paths-ignore creates
    # no run, so it heats nothing, and push events and webhook triggers stay marker-gated.
    # -ceq because GitHub branch names are case-sensitive, and the head_branch check
    # keeps this honest if the push trigger is ever widened beyond development.
    if ([string]$Run.event -eq "push" -and [string]$Run.head_branch -ceq "development") {
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

function ConvertTo-FleetTimestamp {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    # GitHub sends ISO 8601 text, but Invoke-RestMethod on PowerShell 7 has already turned
    # it into a DateTime by the time the controller reads it, while the tests pass the
    # text. Both shapes land here. Anything unreadable is $null so the caller can fail safe.
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [DateTimeOffset]) {
        return $Value
    }
    if ($Value -is [datetime]) {
        return (New-Object -TypeName DateTimeOffset -ArgumentList $Value.ToUniversalTime())
    }
    $parsed = [DateTimeOffset]::MinValue
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([DateTimeOffset]::TryParse([string]$Value, $culture, $styles, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Get-CiRunLastActivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Run
    )

    # The newest of the three stamps. created_at alone would call a re-run of an old run a
    # ghost in the seconds before its new attempt's jobs exist, because a re-run keeps the
    # original created_at and only moves run_started_at and updated_at.
    $latest = $null
    foreach ($field in @("created_at", "run_started_at", "updated_at")) {
        $stamp = ConvertTo-FleetTimestamp -Value $Run.$field
        if ($null -ne $stamp -and ($null -eq $latest -or $stamp -gt $latest)) {
            $latest = $stamp
        }
    }
    $latest
}

function Get-CiRunLane {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Run,
        [Parameter(Mandatory)]
        [string[]]$Maintainers
    )

    # The lane is ci-azure.yml's concurrency group: a maintainer's own, or community.
    $actor = Get-CiRunActor -Run $Run
    if ($actor -in $Maintainers) {
        return $actor
    }
    return "community"
}

function Get-GhostCiRunId {
    [CmdletBinding()]
    param(
        [object[]]$WorkflowRuns = @(),
        [hashtable]$JobsByRun = @{ },
        [object[]]$InProgressRuns = @(),
        [object[]]$QueuedRuns = @(),
        [Parameter(Mandatory)]
        [string[]]$Maintainers,
        [Parameter(Mandatory)]
        [string[]]$OptInPushUsers,
        [Parameter(Mandatory)]
        [string]$Marker,
        [Parameter(Mandatory)]
        [DateTimeOffset]$Now,
        [Parameter(Mandatory)]
        [int]$GhostMinutes
    )

    # A ghost is a run GitHub accepted but never started. On 2026-11-11 an Actions incident
    # left seven ci-azure runs "queued" with no jobs; their workflow file was never evaluated
    # and GitHub refuses to cancel or delete them. Every live run heats its maintainer's lane
    # and a job-less one is estimated as a full pool, so those seven held 15 idle runners for
    # days. A ghost is a live eligible run that
    #   - has no jobs at all, not even the ubuntu authorize job GitHub creates within seconds
    #     of a real run;
    #   - has not moved for GhostMinutes (newest of created_at, run_started_at, updated_at);
    #   - has nothing to wait for: no run in its lane is working. ci-azure.yml queues a
    #     lane's builds behind each other (concurrency queue: max), and a build waiting its
    #     turn looks exactly like a ghost, except that the build ahead of it is running.
    # A lane is working when one of its runs is in_progress, eligible or not (an unmarked
    # manual dispatch runs real jobs and holds the lane as well), or when one of its live
    # eligible runs or any of its queued runs has a job. The build ahead can be older than
    # every run of the WorkflowRuns page, so InProgressRuns and QueuedRuns are the separate
    # in_progress and queued listings. GitHub reports a run's status from its least advanced
    # job, so a started build whose jobs wait for runners can read "queued" rather than
    # "in_progress" (https://github.com/cli/cli/issues/13972). JobsByRun therefore also holds
    # the jobs of QueuedRuns, and a queued run whose jobs were not read holds its lane, since
    # it may be such a build.
    # A run whose jobs were not read is never a ghost, so a failed read keeps the old
    # behavior. Zero disables the check.
    if ($GhostMinutes -le 0) {
        return
    }
    $cutoff = $Now.AddMinutes(-$GhostMinutes)
    $liveRuns = @($WorkflowRuns | Where-Object {
            $splatEligibility = @{
                Run            = $PSItem
                OptInPushUsers = $OptInPushUsers
                Marker         = $Marker
            }
            [string]$PSItem.status -ne "completed" -and (Test-CiRunEligible @splatEligibility)
        })

    $workingLanes = @{ }
    foreach ($run in @(@($WorkflowRuns) + @($InProgressRuns) + @($QueuedRuns) | Where-Object { $null -ne $PSItem })) {
        if ([string]$run.status -eq "in_progress") {
            $workingLanes[(Get-CiRunLane -Run $run -Maintainers $Maintainers)] = $true
        }
    }
    foreach ($run in $liveRuns) {
        $runId = [string]$run.id
        if ($JobsByRun.ContainsKey($runId) -and @($JobsByRun[$runId] | Where-Object { $null -ne $PSItem }).Count -gt 0) {
            $workingLanes[(Get-CiRunLane -Run $run -Maintainers $Maintainers)] = $true
        }
    }
    foreach ($run in @($QueuedRuns | Where-Object { $null -ne $PSItem -and [string]$PSItem.status -ne "completed" })) {
        $runId = [string]$run.id
        if (-not $JobsByRun.ContainsKey($runId) -or @($JobsByRun[$runId] | Where-Object { $null -ne $PSItem }).Count -gt 0) {
            $workingLanes[(Get-CiRunLane -Run $run -Maintainers $Maintainers)] = $true
        }
    }

    foreach ($run in $liveRuns) {
        $runId = [string]$run.id
        if (-not $JobsByRun.ContainsKey($runId)) {
            continue
        }
        if (@($JobsByRun[$runId] | Where-Object { $null -ne $PSItem }).Count -gt 0) {
            continue
        }
        $lastActivity = Get-CiRunLastActivity -Run $run
        if ($null -eq $lastActivity -or $lastActivity -gt $cutoff) {
            continue
        }
        if ($workingLanes.ContainsKey((Get-CiRunLane -Run $run -Maintainers $Maintainers))) {
            continue
        }
        $runId
    }
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

function Get-FleetCapacityStep {
    [CmdletBinding()]
    param(
        [string]$ProvisioningState,
        [int]$NominalCapacity,
        [int]$ActualCapacity,
        [ValidateRange(0, 35)]
        [int]$TargetCapacity
    )

    # The Function controller PATCHes capacity fire-and-forget, so unlike the CLI script
    # it cannot run Get-VmssCapacityPlan's normalize-then-scale sequence: awaiting the
    # normalization would reintroduce the in-line wait that put the queue 3.3 hours
    # behind, and taking one plan step per pass starves scale-out entirely, because
    # ephemeral deletes mint fresh phantom capacity between passes and normalization
    # wins the slot every time -- the fleet drained from 8 VMs to 3 against a target of
    # 20 that way (2026-08-08). So the scale-out step compensates for the drift instead
    # of repairing it first: raising nominal by exactly the shortfall makes Azure create
    # target-minus-actual instances no matter how stale the bookkeeping is, in a single
    # mutation. Normalization above zero members is gone entirely: production proved
    # (2026-08-08, six consecutive observations during the drain, then ten busy runners
    # killed mid-job in one CI run) that a down-PATCH deletes nominal-minus-newValue
    # LIVE instances, and that every capacity PATCH conserves the nominal-over-actual
    # gap, so normalizing can never even catch the drift it chases. The gap grows on
    # per-VM deletes and clears only at the zero-crossing, where a down-PATCH has no
    # members left to take -- that reclaim to zero is the one down-step this function
    # emits. A drifted nominal anywhere above it, runaway or pinned at the ceiling or
    # demand-met surplus, stays untouched and costs at most gap-many slots of ceiling
    # headroom until the fleet next empties on its own. While the scale set is
    # mid-mutation a nominal-over-actual gap is Azure still working, not phantom
    # capacity -- normalizing it away would cancel the instances being created -- so
    # only the ARM terminal states may mutate: an unknown or missing state is
    # indistinguishable from an operation in flight, and the cost of skipping a pass is
    # one safety-tick delay while the cost of overlapping PATCHes is cancelled
    # instances. Failed and Canceled still mutate: a capacity PATCH is how a stuck
    # scale set recovers, and skipping them would freeze the fleet.
    if ($ProvisioningState -notin @("Succeeded", "Failed", "Canceled")) {
        return $null
    }
    if ($NominalCapacity -lt 0 -or $ActualCapacity -lt 0) {
        # Negative telemetry is a garbled ARM read, not a real fleet state, and it must
        # not leak into a PATCH body. Skipping the pass costs one safety tick and the
        # next read starts clean; a ValidateRange would crash the pass instead, which
        # is the exact failure mode the missing attributes above avoid.
        return $null
    }
    if ($ActualCapacity -lt $TargetCapacity) {
        # 35 matches the ValidateRange every capacity function in this file shares.
        # It is the MAX_RUNNERS hard ceiling, and in this function only Target still
        # carries the gate, because the controller chooses it. Nominal and actual are
        # ARM-read telemetry and deliberately carry no range gate: the janitor runbook
        # treats capacity above the ceiling as a real state, and validating it here
        # would crash every pass that observes it -- a ParameterBindingException is not
        # TransientFleetException, so nothing catches it and the controller stops
        # scaling entirely. The min bounds what this function emits; a nominal already
        # at or past the ceiling gets no step here and unwinds through the
        # zero-crossing reclaim below.
        $unclipped = $NominalCapacity + ($TargetCapacity - $ActualCapacity)
        $compensated = [math]::Min(35, $unclipped)
        if ($ActualCapacity -eq 0 -and $NominalCapacity -gt 0 -and $compensated -lt $unclipped) {
            # A clipped step on an empty fleet would create fewer than target instances
            # and then pin there, below target, until the drift unwinds. With zero
            # members the zero-crossing reclaim is free, so repay the whole drift now
            # and let the next pass create the full target from a clean nominal. A
            # clipped step over a nonzero fleet has no such option -- reclaiming would
            # delete the live members -- so it still takes whatever headroom remains.
            return 0
        }
        if ($compensated -gt $NominalCapacity) {
            return $compensated
        }
    }
    if ($ActualCapacity -eq 0 -and $NominalCapacity -gt 0) {
        return 0
    }
    return $null
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

function Get-RunnerDeprecationTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    # One title per runner version, so the daily check can find the issue it opened before.
    # Pass "*" for the -like pattern that matches the issue of any version.
    "CI runner deprecation - GitHub retires actions runner $Version"
}

function Get-RunnerDeprecationNotice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [Parameter(Mandatory)]
        $Deprecation,
        [AllowNull()]
        $LatestRelease,
        [Parameter(Mandatory)]
        [DateTimeOffset]$Now
    )

    # GET /repos/{repo}/actions/runners/deprecations/{version} answers two dates, both null
    # until GitHub schedules the end of a version. Either one stops the fleet: past
    # registration_deprecates_at config.cmd is refused, past runtime_deprecates_at a runner
    # registers and then cannot receive its job, which is how 2.335.1 stopped CI on
    # 2026-11-15. Every fleet VM registers fresh, so the earlier date is the deadline. A
    # date that does not parse counts as due now, because staying quiet is the failure this
    # check exists to prevent.
    $fieldLabels = [ordered]@{
        registration_deprecates_at = "New runners refused from"
        runtime_deprecates_at      = "Jobs refused from"
    }
    $deadline = $null
    $scheduleRows = @()
    foreach ($field in $fieldLabels.Keys) {
        $rawValue = $Deprecation.$field
        if ($null -eq $rawValue -or [string]$rawValue -eq "") {
            $scheduleRows += "| $($fieldLabels[$field]) | not scheduled |"
            continue
        }
        $stamp = ConvertTo-FleetTimestamp -Value $rawValue
        if ($null -eq $stamp) {
            $stamp = $Now
            $scheduleRows += "| $($fieldLabels[$field]) | ``$rawValue`` (unreadable, treated as now) |"
        } else {
            $scheduleRows += "| $($fieldLabels[$field]) | $($stamp.UtcDateTime.ToString("yyyy-MM-dd HH:mm")) UTC |"
        }
        if ($null -eq $deadline -or $stamp -lt $deadline) {
            $deadline = $stamp
        }
    }
    if ($null -eq $deadline) {
        return $null
    }

    $daysLeft = [int][math]::Floor(($deadline - $Now).TotalDays)
    if ($deadline -le $Now) {
        $urgency = "That date has passed, so GitHub refuses runners of this version and CI stops (or is about to)."
    } elseif ($daysLeft -lt 1) {
        $urgency = "That is **less than a day** from now. After it, every new VM registers and then fails, the way 2.335.1 stopped CI on 2026-11-15."
    } else {
        $urgency = "That is **$daysLeft day(s)** from now. After it, every new VM registers and then fails, the way 2.335.1 stopped CI on 2026-11-15."
    }

    $pinFiles = "``.github/runners/bootstrap-runner.ps1`` and ``.github/runners/image-scripts/step1-tools.ps1``"
    $releasesUrl = "https://github.com/actions/runner/releases/latest"
    $latestVersion = $null
    $latestSha256 = $null
    if ($null -ne $LatestRelease) {
        $latestVersion = ([string]$LatestRelease.tag_name) -replace "^v", ""
        if ([string]$LatestRelease.html_url) {
            $releasesUrl = [string]$LatestRelease.html_url
        }
        # the release notes carry each package hash between machine-readable markers
        $shaMatch = [regex]::Match([string]$LatestRelease.body, "BEGIN SHA win-x64 -->\s*([0-9a-fA-F]{64})\s*<!--")
        if ($shaMatch.Success) {
            $latestSha256 = $shaMatch.Groups[1].Value.ToLowerInvariant()
        }
    }
    if ($latestVersion -notmatch "^\d+\.\d+\.\d+$") {
        $fixStep = "1. Pin the latest release from $releasesUrl in $pinFiles. Set ```$runnerVersion`` to its version and ```$runnerSha256`` to the win-x64 SHA256 from its release notes."
    } elseif ($latestVersion -eq $Version) {
        $fixStep = "1. GitHub has published nothing newer than $Version yet. Once it does ($releasesUrl), pin the new release in $pinFiles. Set ```$runnerVersion`` to its version and ```$runnerSha256`` to the win-x64 SHA256 from its release notes."
    } elseif (-not $latestSha256) {
        $fixStep = "1. Pin $latestVersion, the latest release ($releasesUrl), in $pinFiles. Set ```$runnerVersion`` to ``$latestVersion`` and ```$runnerSha256`` to the win-x64 SHA256 from its release notes."
    } else {
        $fixStep = @"
1. Pin $latestVersion, the latest release ($releasesUrl), in ${pinFiles}:

   ``````powershell
   `$runnerVersion = "$latestVersion"
   `$runnerSha256 = "$latestSha256"
   ``````
"@
    }

    $body = @"
GitHub has scheduled the end of actions runner **$Version**, the version ``.github/runners/bootstrap-runner.ps1`` installs on every CI VM.

| | |
|---|---|
$($scheduleRows -join "`n")

$urgency

**To fix**

$fixStep
2. Merge, then deploy the controller with ``.github/runners/deploy-controller.ps1``. The bootstrap ships inside the controller, so the fleet keeps installing $Version until that deploy.
3. Rebuild the golden image with ``.github/runners/build-modern-image.ps1`` and point the VMSS at it. CI works without this step; it only saves each VM the runner download at boot.

The fleet controller checks this every day. It closes this issue once the deployed bootstrap installs another version. Closed by hand while the bootstrap still installs $Version, it opens a new one the next day.
"@

    [pscustomobject]@{
        Title    = Get-RunnerDeprecationTitle -Version $Version
        Body     = $body -replace "`r`n", "`n"
        Deadline = $deadline
        DaysLeft = $daysLeft
    }
}
