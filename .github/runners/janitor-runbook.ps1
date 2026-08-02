<#
.SYNOPSIS
    Azure-side dead man's switch for the dbatools CI runner fleet.

.DESCRIPTION
    Runs every 6 hours from Azure Automation (account: dbatools-ci-janitor,
    runbook: Remove-RunawayRunner), entirely independent of GitHub Actions.
    This is the LAST-DITCH kill switch: the GitHub-side janitor
    (runner-reconcile.yml) owns normal fleet lifecycle; this backstop exists so
    hot capacity cannot idle all day on a wedged dispatch chain.

    The kill rule is keyed to maintainer activity, not the clock:

      - STALE (no eligible activity, checked through anonymous GitHub APIs):
        no runner capacity is preserved; runners older than 1 hour
        are deleted.
      - ACTIVE: ten runners are preserved for every active maintainer -- a LIVE
        ci-azure run or an eligible completed run updated within 20 minutes.
        Community is five while its CI is live, the warm floor within the
        20-minute grace period. Excess runners older than 4 hours die: VM age
        runs from creation, so 45m to register + 20m completion grace + a 90m job
        timeout is ~2.6h of legitimate life, and a tighter cap kills busy VMs.
      - GITHUB UNREACHABLE: we cannot know activity, so conservative age caps
        apply to all capacity -- 3 hours on nights and weekends, 13 hours on
        weekday daytime (06-17 UTC).

    Always, regardless of mode:
      - ps3smoke-* VMs older than 2 hours are deleted (nightly job caps at 55m).
      - Unattached ps3smoke/instance NICs and public IPs are deleted; they
        survive workflows that died mid-teardown and leak money slowly.

    Identity: system-assigned managed identity holding the dbatools-ci-operator
    custom role scoped to the dbatools-ci resource group ONLY. It cannot see
    storage accounts, other resource groups, or role assignments.

    Deployed by hand (see .github/runners/README.md); this file is the
    versioned source of truth for the runbook content.

.NOTES
    Author: the dbatools team + Claude
#>

$ErrorActionPreference = "Continue"
Connect-AzAccount -Identity -WarningAction SilentlyContinue | Out-Null
$rg = "dbatools-ci"
$repo = "dataplat/dbatools"
$maintainers = @("potatoqualitee", "andreasjordan", "niphlod")
$maintainerWindowMinutes = 20
$communityGraceMinutes = 20
$ciMarker = "[do ci]"
$communityPoolSize = 5
$maintainerPoolSize = 10
# Mirrors WARM_FLOOR in runner-reconcile.yml -- kept aligned by a test in
# tests/runner-policy.Tests.ps1. Held only for the community lane while it is hot without a live run.
$warmFloor = 3
$orphanGraceMinutes = 15
$utcNow = (Get-Date).ToUniversalTime()

# ---- recent pool activity (anonymous API, public repo) -------------------------
$mode = "github-unreachable"
$lastActivityAgeHours = $null
$activeMaintainers = @( )
$liveMaintainers = @( )
$communityActive = $false

function Invoke-GitHubGet {
    param([Parameter(Mandatory)][string]$Uri)

    $splatRequest = @{
        Uri        = $Uri
        Headers    = @{ "User-Agent" = "dbatools-ci-janitor" }
        TimeoutSec = 30
    }
    foreach ($attempt in 1..3) {
        try {
            return Invoke-RestMethod @splatRequest
        } catch {
            if ($attempt -eq 3) {
                throw
            }
            Write-Warning "GitHub activity attempt $attempt of 3 failed; retrying. $($PSItem.Exception.Message)"
            Start-Sleep -Seconds (3 * $attempt)
        }
    }
}

function Get-JanitorPushMessage {
    param([Parameter(Mandatory)]$ActivityEvent)

    $head = [string]$ActivityEvent.payload.head
    $headCommit = @($ActivityEvent.payload.commits | Where-Object { [string]$PSItem.sha -eq $head } | Select-Object -First 1)
    if ($headCommit) {
        return [string]$headCommit[0].message
    }
    return ""
}

function Get-JanitorRunActor {
    param([Parameter(Mandatory)]$Run)

    if ([string]$Run.display_title -match "\[pool:([^\]]+)\]") {
        return [string]$Matches[1]
    }
    return [string]$Run.actor.login
}

function Test-JanitorRunEligible {
    param([Parameter(Mandatory)]$Run)

    $actor = Get-JanitorRunActor -Run $Run
    if ($actor -ne "potatoqualitee" -or [string]$Run.event -eq "pull_request") {
        return $true
    }
    $message = "$([string]$Run.head_commit.message) $([string]$Run.display_title)"
    return $message.IndexOf($ciMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Test-JanitorMaintainerEvent {
    param(
        [Parameter(Mandatory)]$ActivityEvent,
        [Parameter(Mandatory)][string]$Maintainer,
        [Parameter(Mandatory)][datetime]$Cutoff
    )

    if ([string]$ActivityEvent.actor.login -ne $Maintainer -or
        ([datetime]::Parse($ActivityEvent.created_at)).ToUniversalTime() -le $Cutoff) {
        return $false
    }
    if ([string]$ActivityEvent.type -eq "PullRequestEvent") {
        return [string]$ActivityEvent.payload.action -in @("opened", "reopened", "synchronize")
    }
    if ([string]$ActivityEvent.type -ne "PushEvent") {
        return $false
    }
    if ($Maintainer -ne "potatoqualitee") {
        return $true
    }
    $message = Get-JanitorPushMessage -ActivityEvent $ActivityEvent
    return $message.IndexOf($ciMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

try {
    $events = @(Invoke-GitHubGet -Uri "https://api.github.com/repos/$repo/events?per_page=100")
    $runResponse = Invoke-GitHubGet -Uri "https://api.github.com/repos/$repo/actions/workflows/ci-azure.yml/runs?per_page=100"
    $runs = @($runResponse.workflow_runs | Where-Object { Test-JanitorRunEligible -Run $PSItem })
    $liveRuns = @($runs | Where-Object { [string]$PSItem.status -ne "completed" })
    $maintainerCutoff = $utcNow.AddMinutes(-$maintainerWindowMinutes)
    $communityCutoff = $utcNow.AddMinutes(-$communityGraceMinutes)

    foreach ($maintainer in $maintainers) {
        $recentActivity = @($events | Where-Object {
                Test-JanitorMaintainerEvent -ActivityEvent $PSItem -Maintainer $maintainer -Cutoff $maintainerCutoff
            }).Count -gt 0
        $liveCi = @($liveRuns | Where-Object { (Get-JanitorRunActor -Run $PSItem) -eq $maintainer }).Count -gt 0
        $recentlyCompletedCi = @($runs | Where-Object {
                (Get-JanitorRunActor -Run $PSItem) -eq $maintainer -and
                [string]$PSItem.status -eq "completed" -and
                ([datetime]::Parse($PSItem.updated_at)).ToUniversalTime() -gt $maintainerCutoff
            }).Count -gt 0
        if ($liveCi) {
            $liveMaintainers += $maintainer
        }
        if ($recentActivity -or $liveCi -or $recentlyCompletedCi) {
            $activeMaintainers += $maintainer
        }
    }

    $communityLive = @($liveRuns | Where-Object {
            (Get-JanitorRunActor -Run $PSItem) -notin $maintainers
        }).Count -gt 0
    $communityRecent = @($runs | Where-Object {
            (Get-JanitorRunActor -Run $PSItem) -notin $maintainers -and
            [string]$PSItem.status -eq "completed" -and
            ([datetime]::Parse($PSItem.updated_at)).ToUniversalTime() -gt $communityCutoff
        }).Count -gt 0
    $communityActive = $communityLive -or $communityRecent

    $activityTimes = @(
        $events | ForEach-Object { ([datetime]::Parse($PSItem.created_at)).ToUniversalTime() }
        $runs | ForEach-Object { ([datetime]::Parse($PSItem.updated_at)).ToUniversalTime() }
    )
    if ($activityTimes) {
        $lastActivity = @($activityTimes | Sort-Object -Descending)[0]
        $lastActivityAgeHours = ($utcNow - $lastActivity).TotalHours
    }
    if ($activeMaintainers.Count -gt 0 -or $communityActive) {
        $mode = "active"
    } else {
        $mode = "stale"
    }
} catch {
    Write-Warning "GitHub activity check failed ($($PSItem.Exception.Message)) -- falling back to age caps"
}

# An active maintainer lane has a fixed ten-runner pool through the 20-minute completion
# grace period. Protection stays per lane; preserving only the fleet-wide total can keep
# another lane's newer VMs instead.
$desiredPools = @{ }
foreach ($maintainer in $activeMaintainers) {
    $desiredPools[$maintainer] = $maintainerPoolSize
}
if ($communityLive) {
    $desiredPools["community"] = $communityPoolSize
} elseif ($communityActive) {
    $desiredPools["community"] = $warmFloor
}
$desiredPoolSize = ($desiredPools.Values | Measure-Object -Sum).Sum
if ($null -eq $desiredPoolSize) {
    $desiredPoolSize = 0
}

switch ($mode) {
    "active" {
        # 4h clears the worst legitimate VM lifetime: 45m to register (:403-404) + 20m
        # completion grace + 90m job timeout (ci-azure.yml) = ~2.6h. Age is
        # measured from VM creation, not from job start, so a cap merely above the job
        # timeout would delete VMs mid-job.
        $runnerMaxHours = 4
        Write-Output "mode=active: maintainers=[$($activeMaintainers -join ", ")] live=[$($liveMaintainers -join ", ")] community=$communityActive -- preserving $desiredPoolSize runners; excess runners past ${runnerMaxHours}h die"
    }
    "stale" {
        $runnerMaxHours = 1
        $ageText = "not in the latest activity window"
        if ($null -ne $lastActivityAgeHours) {
            $ageText = "$([math]::Round($lastActivityAgeHours, 1))h ago"
        }
        Write-Output "mode=stale: last activity $ageText -- no capacity preserved; runners past ${runnerMaxHours}h die"
    }
    default {
        $isWeekend = $utcNow.DayOfWeek -in @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
        $isWeekdayDaytime = (-not $isWeekend) -and $utcNow.Hour -ge 6 -and $utcNow.Hour -lt 17
        if ($isWeekdayDaytime) {
            $runnerMaxHours = 13
        } else {
            $runnerMaxHours = 3
        }
        Write-Output "mode=github-unreachable: conservative age cap ${runnerMaxHours}h"
    }
}

$deleted = 0
$vms = Get-AzVM -ResourceGroupName $rg
$protectedRunners = @()
foreach ($pool in $desiredPools.Keys) {
    $protectedRunners += @(
        $vms |
            Where-Object {
                $PSItem.Name -like "dbatools-runners_*" -and
                $PSItem.Tags -and
                [string]$PSItem.Tags.runnerPool -eq $pool
            } |
            Sort-Object TimeCreated -Descending |
            Select-Object -First $desiredPools[$pool] -ExpandProperty Name
    )
}
Write-Output "found $(@($vms).Count) VM(s) in $rg"
foreach ($vm in $vms) {
    $cap = $null
    if ($vm.Name -like "dbatools-runners_*") {
        if ($vm.Name -in $protectedRunners) {
            Write-Output "preserving desired-pool runner $($vm.Name)"
            continue
        }
        $cap = $runnerMaxHours
    } elseif ($vm.Name -like "ps3smoke*") {
        $cap = 2
    }
    if (-not $cap) {
        Write-Output "skipping unmanaged VM $($vm.Name)"
        continue
    }

    # a VM with no readable creation time is treated as ancient: every VM in
    # this resource group is throwaway by design, so failing open deletes it
    $ageHours = 999
    if ($vm.TimeCreated) {
        $ageHours = ($utcNow - $vm.TimeCreated.ToUniversalTime()).TotalHours
    }
    if ($ageHours -gt $cap) {
        Write-Warning "RUNAWAY: $($vm.Name) is $([math]::Round($ageHours, 1))h old (cap ${cap}h, mode $mode) -- deleting"
        $null = Remove-AzVM -ResourceGroupName $rg -Name $vm.Name -Force
        $deleted++
    } else {
        Write-Output "ok: $($vm.Name) age $([math]::Round($ageHours, 1))h"
    }
}

# Orphaned NICs and public IPs survive a workflow that died between VM delete and
# network teardown. A newly provisioning VM can also leave its networking unattached
# briefly, so only matching resources older than the grace period are garbage.
function Test-JanitorOrphanOldEnough {
    param([Parameter(Mandatory)]$Resource)

    if (-not $Resource.Id) {
        Write-Warning "preserving orphan candidate $($Resource.Name); resource ID is unavailable"
        return $false
    }
    try {
        $splatResource = @{
            ResourceId       = $Resource.Id
            ExpandProperties = $true
            ErrorAction      = "Stop"
        }
        $resourceDetails = Get-AzResource @splatResource
    } catch {
        Write-Warning "preserving orphan candidate $($Resource.Name); creation time lookup failed: $($PSItem.Exception.Message)"
        return $false
    }
    if (-not $resourceDetails.CreatedTime) {
        Write-Warning "preserving orphan candidate $($Resource.Name); creation time is unavailable"
        return $false
    }
    $ageMinutes = ($utcNow - ([datetime]$resourceDetails.CreatedTime).ToUniversalTime()).TotalMinutes
    return $ageMinutes -ge $orphanGraceMinutes
}

foreach ($nic in Get-AzNetworkInterface -ResourceGroupName $rg) {
    if ($nic.VirtualMachine) {
        continue
    }
    if (($nic.Name -like "ps3smoke*" -or $nic.Name -like "*Nic-*") -and
        (Test-JanitorOrphanOldEnough -Resource $nic)) {
        Write-Warning "orphaned NIC $($nic.Name) -- deleting"
        $null = Remove-AzNetworkInterface -ResourceGroupName $rg -Name $nic.Name -Force
        $deleted++
    }
}
foreach ($pip in Get-AzPublicIpAddress -ResourceGroupName $rg) {
    if ($pip.IpConfiguration) {
        continue
    }
    if (($pip.Name -like "ps3smoke*" -or $pip.Name -like "instancepublicip-*") -and
        (Test-JanitorOrphanOldEnough -Resource $pip)) {
        Write-Warning "orphaned public IP $($pip.Name) -- deleting"
        $null = Remove-AzPublicIpAddress -ResourceGroupName $rg -Name $pip.Name -Force
        $deleted++
    }
}

$vmss = Get-AzVmss -ResourceGroupName $rg -VMScaleSetName "dbatools-runners" -ErrorAction SilentlyContinue
if ($vmss -and $vmss.Sku.Capacity -gt 35) {
    Write-Warning "VMSS capacity is $($vmss.Sku.Capacity) -- above the hard fleet limit (MAX_RUNNERS is 35)"
}

if ($deleted -gt 0) {
    Write-Warning "janitor deleted $deleted resource(s) -- check whether the GitHub-side reconcile machinery is dead"
} else {
    Write-Output "nothing runaway; bill is safe"
}
