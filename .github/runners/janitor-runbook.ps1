<#
.SYNOPSIS
    Azure-side dead man's switch for the dbatools CI runner fleet.

.DESCRIPTION
    Runs every 6 hours from Azure Automation (account: dbatools-ci-janitor,
    runbook: Remove-RunawayRunner), entirely independent of GitHub. The
    GitHub-side janitor (runner-reconcile.yml) reaps spent and zombie VMs within
    minutes; this backstop only matters when that machinery is dead -- GitHub
    outage, broken workflow file, lost dispatch chain. It deletes:

      - dbatools-runners_* instances older than the age cap: 3h on nights and
        weekends, 13h during weekday daytime (06-17 UTC) so the reconcile
        standby floor can idle legitimately. A runner doing real work lives
        ~100 minutes at most (90-minute job timeout plus boot).
      - ps3smoke-* VMs older than 2 hours (the nightly job caps at 55 minutes).
      - unattached ps3smoke/instance NICs and public IPs, which survive a
        workflow that died mid-teardown and leak a few dollars a month each.

    Identity: system-assigned managed identity holding the dbatools-ci-operator
    custom role scoped to the dbatools-ci resource group ONLY. It cannot see
    storage accounts, other resource groups, or role assignments.

    Deployed by hand (see .github/runners/README.md); this file is the
    versioned source of truth for the runbook content.

.NOTES
    Author: the dbatools team + Claude
#>

$ErrorActionPreference = "Continue"
$null = Connect-AzAccount -Identity
$rg = "dbatools-ci"
$utcNow = (Get-Date).ToUniversalTime()

$isWeekend = $utcNow.DayOfWeek -in @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
$isWeekdayDaytime = (-not $isWeekend) -and $utcNow.Hour -ge 6 -and $utcNow.Hour -lt 17
if ($isWeekdayDaytime) {
    $runnerMaxHours = 13
} else {
    $runnerMaxHours = 3
}
Write-Output "scan $($utcNow.ToString("u")): runner age cap ${runnerMaxHours}h, smoke cap 2h"

$deleted = 0
$vms = Get-AzVM -ResourceGroupName $rg
Write-Output "found $(@($vms).Count) VM(s) in $rg"
foreach ($vm in $vms) {
    $cap = $null
    if ($vm.Name -like "dbatools-runners_*") {
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
        Write-Warning "RUNAWAY: $($vm.Name) is $([math]::Round($ageHours, 1))h old (cap ${cap}h) -- deleting"
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
if ($vmss -and $vmss.Sku.Capacity -gt 12) {
    Write-Warning "VMSS capacity is $($vmss.Sku.Capacity) -- above any sane fleet size (MAX_RUNNERS is 10)"
}

if ($deleted -gt 0) {
    Write-Warning "janitor deleted $deleted resource(s) -- check whether the GitHub-side reconcile machinery is dead"
} else {
    Write-Output "nothing runaway; bill is safe"
}
