<#
.SYNOPSIS
    Azure-side dead man's switch for the dbatools CI runner fleet.

.DESCRIPTION
    Runs every 6 hours from Azure Automation (account: dbatools-ci-janitor,
    runbook: Remove-RunawayRunner), entirely independent of GitHub Actions.
    This is the LAST-DITCH kill switch: the GitHub-side janitor
    (runner-reconcile.yml) owns normal fleet lifecycle; this backstop exists so
    capacity above the intentional five-runner baseline cannot idle all day on
    a wedged dispatch chain.

    The kill rule is keyed to maintainer activity, not the clock:

      - STALE (no push by a maintainer in the last 2 hours, checked through the
        anonymous GitHub events API): the five newest community-pool runners are
        preserved and excess runners older than 2 hours are deleted.
      - ACTIVE (maintainer push within 2 hours): ten runners are preserved for
        each active maintainer; excess runners older than 2 hours are deleted.
      - GITHUB UNREACHABLE: we cannot know activity, so conservative age caps
        apply to capacity above the preserved five-runner community pool -- 3
        hours on nights and weekends, 13 hours on weekday daytime (06-17 UTC).

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
$maintainers = @("potatoqualitee", "andreasjordan")
$activityWindowHours = 2
$communityPoolSize = 5
$maintainerPoolSize = 10
$utcNow = (Get-Date).ToUniversalTime()

# ---- how long since the last maintainer push? (anonymous API, public repo) ----
$mode = "github-unreachable"
$lastPushAgeHours = $null
$activeMaintainers = @( )
try {
    $splatEvents = @{
        Uri        = "https://api.github.com/repos/$repo/events?per_page=100"
        Headers    = @{ "User-Agent" = "dbatools-ci-janitor" }
        TimeoutSec = 30
    }
    $events = $null
    foreach ($attempt in 1..3) {
        try {
            $events = Invoke-RestMethod @splatEvents
            break
        } catch {
            if ($attempt -eq 3) {
                throw
            }
            Write-Warning "GitHub activity attempt $attempt of 3 failed; retrying. $($PSItem.Exception.Message)"
            Start-Sleep -Seconds (3 * $attempt)
        }
    }
    $pushes = @($events | Where-Object { $PSItem.type -eq "PushEvent" -and $PSItem.actor.login -in $maintainers })
    if ($pushes) {
        $lastPush = ($pushes | ForEach-Object { ([datetime]::Parse($PSItem.created_at)).ToUniversalTime() } | Sort-Object -Descending)[0]
        $lastPushAgeHours = ($utcNow - $lastPush).TotalHours
        foreach ($maintainer in $maintainers) {
            $maintainerPushes = @($pushes | Where-Object { $PSItem.actor.login -eq $maintainer })
            if (-not $maintainerPushes) {
                continue
            }
            $latestMaintainerPush = ($maintainerPushes | ForEach-Object { ([datetime]::Parse($PSItem.created_at)).ToUniversalTime() } | Sort-Object -Descending)[0]
            if (($utcNow - $latestMaintainerPush).TotalHours -le $activityWindowHours) {
                $activeMaintainers += $maintainer
            }
        }
        if ($activeMaintainers.Count -gt 0) {
            $mode = "active"
        } else {
            $mode = "stale"
        }
    } else {
        # no maintainer push within the last ~100 repo events: definitely stale
        $mode = "stale"
    }
} catch {
    Write-Warning "GitHub activity check failed ($($PSItem.Exception.Message)) -- falling back to age caps"
}

$desiredPoolSize = $communityPoolSize
if ($activeMaintainers.Count -gt 0) {
    $desiredPoolSize = $activeMaintainers.Count * $maintainerPoolSize
}

switch ($mode) {
    "active" {
        $runnerMaxHours = 2
        Write-Output "mode=active: $($activeMaintainers.Count) maintainer(s) [$($activeMaintainers -join ', ')] -- preserving $desiredPoolSize runners; excess runners past ${runnerMaxHours}h die"
    }
    "stale" {
        $runnerMaxHours = 2
        $ageText = "not in the last 100 events"
        if ($null -ne $lastPushAgeHours) {
            $ageText = "$([math]::Round($lastPushAgeHours, 1))h ago"
        }
        Write-Output "mode=stale: last maintainer push $ageText -- excess runners past ${runnerMaxHours}h die; five newest are preserved"
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
$protectedRunners = @(
    $vms |
        Where-Object Name -Like "dbatools-runners_*" |
        Sort-Object TimeCreated -Descending |
        Select-Object -First $desiredPoolSize -ExpandProperty Name
)
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

# orphaned NICs and public IPs survive a workflow that died between VM delete
# and network teardown; unattached ones matching CI naming are always garbage
foreach ($nic in Get-AzNetworkInterface -ResourceGroupName $rg) {
    if ($nic.VirtualMachine) {
        continue
    }
    if ($nic.Name -like "ps3smoke*" -or $nic.Name -like "*Nic-*") {
        Write-Warning "orphaned NIC $($nic.Name) -- deleting"
        $null = Remove-AzNetworkInterface -ResourceGroupName $rg -Name $nic.Name -Force
        $deleted++
    }
}
foreach ($pip in Get-AzPublicIpAddress -ResourceGroupName $rg) {
    if ($pip.IpConfiguration) {
        continue
    }
    if ($pip.Name -like "ps3smoke*" -or $pip.Name -like "instancepublicip-*") {
        Write-Warning "orphaned public IP $($pip.Name) -- deleting"
        $null = Remove-AzPublicIpAddress -ResourceGroupName $rg -Name $pip.Name -Force
        $deleted++
    }
}

$vmss = Get-AzVmss -ResourceGroupName $rg -VMScaleSetName "dbatools-runners" -ErrorAction SilentlyContinue
if ($vmss -and $vmss.Sku.Capacity -gt 22) {
    Write-Warning "VMSS capacity is $($vmss.Sku.Capacity) -- above any sane fleet size (MAX_RUNNERS is 20)"
}

if ($deleted -gt 0) {
    Write-Warning "janitor deleted $deleted resource(s) -- check whether the GitHub-side reconcile machinery is dead"
} else {
    Write-Output "nothing runaway; bill is safe"
}
