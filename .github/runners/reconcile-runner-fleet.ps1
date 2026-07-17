<#
.SYNOPSIS
    Reconciles the AppVeyor-style GitHub Actions worker pools on the Azure VMSS.

.DESCRIPTION
    Maintains four logical pools on one Flexible VMSS. Individual VMs retain their
    pool assignment in the runnerPool tag and register with a matching GitHub runner
    label. Runner agents are ephemeral; a VM is deleted after its single job and its
    pool slot is replaced from the golden image.

    External control-plane calls are retried three times. Exhausted control-plane
    failures throw TransientFleetException so the workflow can bail out green without
    making scaling decisions from incomplete state. Logic errors still fail normally.
#>

class TransientFleetException : System.Exception {
    TransientFleetException([string]$message) : base($message) { }
}

$ErrorActionPreference = "Stop"
$repo = $env:REPO
$resourceGroup = $env:RG
$vmss = $env:VMSS
$runnerLabel = $env:RUNNER_LABEL
$poolLabelPrefix = "dbatools-pool-"
$communityCount = if ($env:COMMUNITY_COUNT) { [int]$env:COMMUNITY_COUNT } else { 5 }
$maintainerCount = if ($env:BOOST_COUNT) { [int]$env:BOOST_COUNT } else { 10 }
$maintainerWindowMinutes = if ($env:BOOST_HOURS) { [int]$env:BOOST_HOURS * 60 } else { 60 }
$communityGraceMinutes = if ($env:COMMUNITY_GRACE_MINUTES) { [int]$env:COMMUNITY_GRACE_MINUTES } else { 20 }
$maxRunners = if ($env:MAX_RUNNERS) { [int]$env:MAX_RUNNERS } else { 35 }
$maintainers = @($env:BOOST_USERS -split "\s+" | Where-Object { $PSItem })
$optInPushUsers = @($env:OPT_IN_PUSH_USERS -split "\s+" | Where-Object { $PSItem })
$ciMarker = if ($env:CI_MARKER) { $env:CI_MARKER } else { "[do ci]" }
$bootstrapPath = $env:BOOTSTRAP_PATH
$deletedVms = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$policyPath = $env:POLICY_PATH
$workflowToken = $env:WORKFLOW_TOKEN

$missingSettings = @(
    @{ Name = "REPO"; Value = $repo }, @{ Name = "RG"; Value = $resourceGroup },
    @{ Name = "VMSS"; Value = $vmss }, @{ Name = "RUNNER_LABEL"; Value = $runnerLabel },
    @{ Name = "BOOTSTRAP_PATH"; Value = $bootstrapPath },
    @{ Name = "POLICY_PATH"; Value = $policyPath },
    @{ Name = "WORKFLOW_TOKEN"; Value = $workflowToken }
    | Where-Object { -not $PSItem.Value } | ForEach-Object Name
)
if ($missingSettings) {
    throw "Missing required fleet settings: $($missingSettings -join ', ')"
}

. $policyPath

function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    foreach ($attempt in 1..3) {
        try {
            return & $Action
        } catch {
            if ($attempt -eq 3) {
                throw [TransientFleetException]::new("$Operation failed after 3 attempts. $($PSItem.Exception.Message)")
            }
            Write-Warning "$Operation attempt $attempt of 3 failed; retrying. $($PSItem.Exception.Message)"
            Start-Sleep -Seconds (3 * $attempt)
        }
    }
}

function Invoke-NativeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [Parameter(Mandatory)]
        [string]$Operation
    )

    Invoke-WithRetry -Operation $Operation -Action {
        $output = @(& $Tool @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw ($output -join [Environment]::NewLine)
        }
        $output -join [Environment]::NewLine
    }
}

function Invoke-NativeJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [Parameter(Mandatory)]
        [string]$Operation
    )

    $text = Invoke-NativeText -Tool $Tool -Arguments $Arguments -Operation $Operation
    if (-not $text) {
        return $null
    }
    $text | ConvertFrom-Json -Depth 20
}

function Invoke-GhJson {
    param([string[]]$Arguments, [string]$Operation)
    Invoke-NativeJson -Tool "gh" -Arguments (@("api") + $Arguments) -Operation $Operation
}

function Invoke-AzJson {
    param([string[]]$Arguments, [string]$Operation)
    Invoke-NativeJson -Tool "az" -Arguments ($Arguments + @("--only-show-errors", "--output", "json")) -Operation $Operation
}

function Get-RunnerPool {
    param($Runner)
    if (-not $Runner) {
        return $null
    }
    $label = @($Runner.labels.name | Where-Object { $PSItem -like "$poolLabelPrefix*" } | Select-Object -First 1)
    if (-not $label) {
        return $null
    }
    $label[0].Substring($poolLabelPrefix.Length)
}

function Get-VmPool {
    param($Vm)
    if ($Vm.tags -and $Vm.tags.runnerPool) {
        return [string]$Vm.tags.runnerPool
    }
    return $null
}

function Get-VmAgeMinutes {
    param($Vm)
    if (-not $Vm.created) {
        return 0
    }
    [int](([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse($Vm.created)).TotalMinutes)
}


function Get-FleetState {
    $runnerResponse = Invoke-GhJson -Arguments @("repos/$repo/actions/runners?per_page=100") -Operation "list GitHub runners"
    $runners = @($runnerResponse.runners | Where-Object { $PSItem.labels.name -contains $runnerLabel })
    $vmQuery = "[?starts_with(name, '${vmss}_')].{name:name,created:timeCreated,power:powerState,provisioning:provisioningState,tags:tags}"
    $vms = @(Invoke-AzJson -Arguments @("vm", "list", "--resource-group", $resourceGroup, "--show-details", "--query", $vmQuery) -Operation "list Azure runner VMs")
    [pscustomobject]@{ Runners = $runners; Vms = $vms }
}

function Get-RunnerForVm {
    param($State, [string]$VmName)
    @($State.Runners | Where-Object name -EQ $VmName | Select-Object -First 1)[0]
}

function Set-VmPool {
    param([string]$VmName, [string]$Pool)
    # Use the dedicated tag API. `az vm update --set tags.*` can invoke Azure's
    # unrelated zone-movement validation and reject otherwise valid VM tag changes.
    $vmId = Invoke-AzJson -Arguments @(
        "vm", "show", "--resource-group", $resourceGroup, "--name", $VmName, "--query", "id"
    ) -Operation "read resource ID for $VmName"
    $null = Invoke-NativeText -Tool "az" -Arguments @(
        "tag", "update", "--resource-id", $vmId, "--operation", "Merge",
        "--tags", "runnerPool=$Pool", "--only-show-errors", "--output", "none"
    ) -Operation "tag $VmName for pool $Pool"
    Write-Host "assigned $VmName to pool $Pool"
}

function Remove-FleetVm {
    param($State, $Vm, [string]$Reason)
    if (-not $deletedVms.Add($Vm.name)) {
        return
    }
    $runner = Get-RunnerForVm -State $State -VmName $Vm.name
    if ($runner -and $runner.busy) {
        $null = $deletedVms.Remove($Vm.name)
        Write-Host "preserving busy $($Vm.name) despite: $Reason"
        return
    }
    Write-Host "deleting $($Vm.name) -- $Reason"
    if ($runner) {
        try {
            $null = Invoke-NativeText -Tool "gh" -Arguments @(
                "api", "--method", "DELETE", "repos/$repo/actions/runners/$($runner.id)"
            ) -Operation "remove runner record $($runner.name)"
        } catch [TransientFleetException] {
            if ($PSItem.Exception.Message -notmatch "currently running a job") {
                throw
            }
            $null = $deletedVms.Remove($Vm.name)
            Write-Host "preserving $($Vm.name); it accepted a job during the deletion check"
            return
        }
    }
    $null = Invoke-NativeText -Tool "az" -Arguments @(
        "vm", "delete", "--resource-group", $resourceGroup, "--name", $Vm.name,
        "--yes", "--only-show-errors", "--output", "none"
    ) -Operation "delete VM $($Vm.name)"
}

function Get-RunnerDemand {
    $events = @(Invoke-GhJson -Arguments @("repos/$repo/events?per_page=100") -Operation "read repository activity")
    $runResponse = Invoke-GhJson -Arguments @(
        "repos/$repo/actions/workflows/ci-azure.yml/runs?per_page=100"
    ) -Operation "read CI build queue"
    $workflowRuns = @($runResponse.workflow_runs)
    $now = [DateTimeOffset]::UtcNow
    $splatPolicy = @{
        Events                  = $events
        WorkflowRuns            = $workflowRuns
        Maintainers             = $maintainers
        OptInPushUsers          = $optInPushUsers
        MaintainerCount         = $maintainerCount
        MaintainerWindowMinutes = $maintainerWindowMinutes
        CommunityCount          = $communityCount
        CommunityGraceMinutes   = $communityGraceMinutes
        MaxRunners              = $maxRunners
        Marker                  = $ciMarker
        Now                     = $now
        DirectTriggerActor      = [string]$env:BOOST_TRIGGER
        DirectTriggerMessage    = [string]$env:BOOST_MESSAGE
    }
    $desired = Get-DesiredRunnerPools @splatPolicy

    $total = ($desired.Values | Measure-Object -Sum).Sum
    Write-Host "desired pools: $(($desired.GetEnumerator() | ForEach-Object { "$($PSItem.Key)=$($PSItem.Value)" }) -join ', ') total=$total"
    $splatDispatch = @{
        Events               = $events
        WorkflowRuns         = $workflowRuns
        OptInPushUsers       = $optInPushUsers
        Marker               = $ciMarker
        Cutoff               = $now.AddMinutes(-$maintainerWindowMinutes)
        DirectTriggerActor   = [string]$env:BOOST_TRIGGER
        DirectTriggerMessage = [string]$env:BOOST_MESSAGE
        DirectTriggerSha     = [string]$env:BOOST_SHA
        DirectTriggerRef     = [string]$env:BOOST_REF
    }
    [pscustomobject]@{
        Desired  = $desired
        Dispatch = Get-MarkedPushDispatch @splatDispatch
    }
}

function Invoke-MarkedCiDispatch {
    param(
        [Parameter(Mandatory)]
        $Request
    )

    $body = @{
        ref    = $Request.Ref
        inputs = @{ message = $Request.Message; pool_user = $Request.Actor }
    } | ConvertTo-Json -Depth 4
    $splatDispatch = @{
        Method      = "Post"
        Uri         = "https://api.github.com/repos/$repo/actions/workflows/ci-azure.yml/dispatches"
        Headers     = @{
            Accept                 = "application/vnd.github+json"
            Authorization          = "Bearer $workflowToken"
            "X-GitHub-Api-Version" = "2022-11-28"
        }
        Body        = $body
        ContentType = "application/json"
        TimeoutSec  = 30
    }
    $null = Invoke-WithRetry -Operation "dispatch marked CI for $($Request.Sha)" -Action {
        Invoke-RestMethod @splatDispatch
    }
    Write-Host "dispatched marked CI ref=$($Request.Ref) sha=$($Request.Sha)"
}

function Assign-UnallocatedVms {
    param($State, $Desired)
    $available = [System.Collections.Generic.Queue[object]]::new()
    foreach ($vm in $State.Vms | Sort-Object created) {
        $runner = Get-RunnerForVm -State $State -VmName $vm.name
        if (-not (Get-VmPool -Vm $vm) -and -not $runner) {
            $available.Enqueue($vm)
        }
    }

    foreach ($pool in $Desired.Keys) {
        $current = @($State.Vms | Where-Object { (Get-VmPool -Vm $PSItem) -eq $pool }).Count
        $deficit = $Desired[$pool] - $current
        while ($deficit -gt 0 -and $available.Count -gt 0) {
            $vm = $available.Dequeue()
            Set-VmPool -VmName $vm.name -Pool $pool
            $deficit--
        }
    }
}

function Register-PoolVms {
    param($State, $Desired)
    $tasks = @()
    foreach ($vm in $State.Vms) {
        $pool = Get-VmPool -Vm $vm
        $runner = Get-RunnerForVm -State $State -VmName $vm.name
        if (-not $pool -or $Desired[$pool] -le 0 -or ($runner -and $runner.status -ne "offline")) {
            continue
        }
        # Probe offline ephemeral runners too. The bootstrap distinguishes a VM that
        # is still starting from one whose runner already served its single job.
        $tokenResponse = Invoke-GhJson -Arguments @(
            "--method", "POST", "repos/$repo/actions/runners/registration-token"
        ) -Operation "mint registration token for $($vm.name)"
        $tasks += [pscustomobject]@{
            VmName = $vm.name
            Token = $tokenResponse.token
            Labels = "$runnerLabel,$poolLabelPrefix$pool"
        }
    }
    if (-not $tasks) {
        return
    }

    Write-Host "registering $($tasks.Count) pool runner(s)"
    $results = $tasks | ForEach-Object -Parallel {
        $result = $null
        foreach ($attempt in 1..3) {
            $output = @(& az vm run-command invoke --resource-group $using:resourceGroup --name $PSItem.VmName `
                    --command-id RunPowerShellScript --scripts "@$using:bootstrapPath" `
                    --parameters "Token=$($PSItem.Token)" "RunnerName=$($PSItem.VmName)" "Labels=$($PSItem.Labels)" `
                    --query "value[0].message" --output tsv --only-show-errors 2>&1)
            $code = $LASTEXITCODE
            $outputText = $output -join [Environment]::NewLine
            if ($outputText -match "SPENT-VM") {
                $result = [pscustomobject]@{ VmName = $PSItem.VmName; Succeeded = $true; Output = $outputText }
                break
            }
            if ($code -eq 0) {
                $result = [pscustomobject]@{ VmName = $PSItem.VmName; Succeeded = $true; Output = $outputText }
                break
            }
            if ($attempt -lt 3) {
                Start-Sleep -Seconds (3 * $attempt)
            } else {
                $result = [pscustomobject]@{ VmName = $PSItem.VmName; Succeeded = $false; Output = $outputText }
            }
        }
        $result
    } -ThrottleLimit 25

    foreach ($result in $results) {
        if (-not $result.Succeeded) {
            Write-Warning "Registration for $($result.VmName) exhausted retries; leaving it for the next reconcile. $($result.Output)"
            continue
        }
        Write-Host (($result.Output -split "`r?`n" | Select-Object -Last 3) -join [Environment]::NewLine)
        if ($result.Output -match "SPENT-VM") {
            $vm = @($State.Vms | Where-Object name -EQ $result.VmName | Select-Object -First 1)[0]
            Remove-FleetVm -State $State -Vm $vm -Reason "ephemeral runner already served a job"
        }
    }
}

try {
    $demand = Get-RunnerDemand
    if ($demand.Dispatch) {
        Invoke-MarkedCiDispatch -Request $demand.Dispatch
    }
    $desired = $demand.Desired
    $desiredTotal = ($desired.Values | Measure-Object -Sum).Sum
    $state = Get-FleetState

    # Migrate or remove generic pre-pool runners without interrupting active jobs.
    foreach ($vm in $state.Vms) {
        $runner = Get-RunnerForVm -State $state -VmName $vm.name
        $vmPool = Get-VmPool -Vm $vm
        $runnerPool = Get-RunnerPool -Runner $runner
        if (-not $vmPool -and $runnerPool) {
            Set-VmPool -VmName $vm.name -Pool $runnerPool
        } elseif ($runner -and -not $runnerPool -and -not $runner.busy) {
            Remove-FleetVm -State $state -Vm $vm -Reason "legacy runner lacks a pool label"
        }
    }

    $state = Get-FleetState
    Assign-UnallocatedVms -State $state -Desired $desired
    $state = Get-FleetState
    Register-PoolVms -State $state -Desired $desired
    $state = Get-FleetState

    # Remove dead runners and trim pools whose hot window has ended.
    foreach ($vm in $state.Vms) {
        $pool = Get-VmPool -Vm $vm
        $runner = Get-RunnerForVm -State $state -VmName $vm.name
        $ageMinutes = Get-VmAgeMinutes -Vm $vm
        if (-not $pool -and -not $runner) {
            Remove-FleetVm -State $state -Vm $vm -Reason "unallocated capacity exceeds all active pool targets"
        } elseif ($runner -and $runner.status -eq "offline" -and $ageMinutes -gt 15) {
            Remove-FleetVm -State $state -Vm $vm -Reason "runner offline after bootstrap grace period"
        } elseif (-not $runner -and $pool -and $ageMinutes -gt 45) {
            Remove-FleetVm -State $state -Vm $vm -Reason "never registered after 45 minutes"
        }
    }

    $state = Get-FleetState
    foreach ($pool in $desired.Keys) {
        $poolVms = @($state.Vms | Where-Object { (Get-VmPool -Vm $PSItem) -eq $pool } | Sort-Object created)
        $excess = $poolVms.Count - $desired[$pool]
        foreach ($vm in $poolVms) {
            if ($excess -le 0) {
                break
            }
            $runner = Get-RunnerForVm -State $state -VmName $vm.name
            if ($runner -and $runner.busy) {
                continue
            }
            Remove-FleetVm -State $state -Vm $vm -Reason "pool $pool is $excess above desired capacity"
            $excess--
        }
    }

    $state = Get-FleetState
    $transitionBusy = @($state.Vms | Where-Object {
            $runner = Get-RunnerForVm -State $state -VmName $PSItem.name
            $pool = Get-VmPool -Vm $PSItem
            $outsideDesiredPool = -not $pool -or -not $desired.Contains($pool) -or $desired[$pool] -eq 0
            $outsideDesiredPool -and $runner -and $runner.busy
        }).Count
    $target = [math]::Min($maxRunners, $desiredTotal + $transitionBusy)
    $capacityResponse = Invoke-AzJson -Arguments @(
        "vmss", "show", "--resource-group", $resourceGroup, "--name", $vmss,
        "--query", "{capacity:sku.capacity}"
    ) -Operation "read VMSS capacity"
    $capacity = [int]$capacityResponse.capacity
    Write-Host "capacity=$capacity target=$target transition_busy=$transitionBusy"
    if ($capacity -lt $target) {
        $null = Invoke-NativeText -Tool "az" -Arguments @(
            "vmss", "scale", "--resource-group", $resourceGroup, "--name", $vmss,
            "--new-capacity", "$target", "--no-wait", "--only-show-errors", "--output", "none"
        ) -Operation "scale VMSS to $target"
        foreach ($attempt in 1..15) {
            Start-Sleep -Seconds 20
            $state = Get-FleetState
            $notReady = @($state.Vms | Where-Object provisioning -NE "Succeeded").Count
            if ($state.Vms.Count -ge $target -and $notReady -eq 0) {
                break
            }
            Write-Host "provisioning check $attempt of 15: vms=$($state.Vms.Count)/$target not_ready=$notReady"
        }
    }

    $state = Get-FleetState
    Assign-UnallocatedVms -State $state -Desired $desired
    $state = Get-FleetState
    Register-PoolVms -State $state -Desired $desired
    $state = Get-FleetState
    foreach ($pool in $desired.Keys) {
        $poolVms = @($state.Vms | Where-Object { (Get-VmPool -Vm $PSItem) -eq $pool })
        $poolRunners = @($state.Runners | Where-Object { (Get-RunnerPool -Runner $PSItem) -eq $pool })
        $online = @($poolRunners | Where-Object status -EQ "online").Count
        $busy = @($poolRunners | Where-Object busy).Count
        Write-Host "pool=$pool desired=$($desired[$pool]) vms=$($poolVms.Count) online=$online busy=$busy"
    }
} catch [TransientFleetException] {
    Write-Warning "$($PSItem.Exception.Message) No further fleet changes will be attempted; a job-completion nudge or scheduled reconcile will retry."
    exit 0
}
