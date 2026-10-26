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
$maintainerWindowMinutes = if ($env:BOOST_MINUTES) { [int]$env:BOOST_MINUTES } elseif ($env:BOOST_HOURS) { [int]$env:BOOST_HOURS * 60 } else { 20 }
$communityGraceMinutes = if ($env:COMMUNITY_GRACE_MINUTES) { [int]$env:COMMUNITY_GRACE_MINUTES } else { 20 }
$maxRunners = if ($env:MAX_RUNNERS) { [int]$env:MAX_RUNNERS } else { 35 }
$warmFloor = if ($env:WARM_FLOOR) { [int]$env:WARM_FLOOR } else { 0 }
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

function Set-VmTimestampTag {
    param(
        [string]$VmName,
        [string]$TagName
    )
    $vmId = Invoke-AzJson -Arguments @(
        "vm", "show", "--resource-group", $resourceGroup, "--name", $VmName, "--query", "id"
    ) -Operation "read resource ID for $VmName"
    $stamp = [DateTimeOffset]::UtcNow.ToString("o")
    $splatTag = @{
        Tool      = "az"
        Arguments = @(
            "tag", "update", "--resource-id", $vmId, "--operation", "Merge",
            "--tags", "$TagName=$stamp", "--only-show-errors", "--output", "none"
        )
        Operation = "stamp $VmName $TagName"
    }
    $null = Invoke-NativeText @splatTag
}

function Set-VmRegisteredAt {
    param([string]$VmName)
    # Records when bootstrap finished registering the runner. Paired with the VM's
    # creation time in Remove-FleetVm, this separates boot overhead from hot-idle
    # time -- the two are indistinguishable in Azure cost data alone.
    Set-VmTimestampTag -VmName $VmName -TagName "registeredAt"
}

function Set-VmOnlineObservedAt {
    param($State, $Vms)
    # Records when the controller first observes a runner online. This is an upper bound
    # on listener startup, not its exact timestamp: observation is delayed by up to the
    # five-minute reconcile interval. It still separates startup from longer hot-idle
    # waiting without granting the runner an Azure identity.
    #
    # The controller does this rather than the VM because runner VMs hold no Azure
    # identity and must not gain one. Resolution is therefore the reconcile interval.
    foreach ($vm in $Vms) {
        if (-not $vm.tags -or -not $vm.tags.registeredAt -or $vm.tags.onlineObservedAt) {
            continue
        }
        $runner = Get-RunnerForVm -State $State -VmName $vm.name
        if (-not $runner -or $runner.status -ne "online") {
            continue
        }
        Set-VmTimestampTag -VmName $vm.name -TagName "onlineObservedAt"
    }
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
    # bootMin is creation to runner registration. onlineObservedMin is registration to
    # the controller's first online observation, so it is a reconcile-resolution upper
    # bound on listener startup rather than an exact reboot duration.
    $bootMin = "unknown"
    $onlineObservedMin = "unknown"
    if ($Vm.tags -and $Vm.tags.registeredAt) {
        $registered = [DateTimeOffset]::Parse([string]$Vm.tags.registeredAt)
        $created = [DateTimeOffset]::Parse([string]$Vm.created)
        $bootMin = [int]($registered - $created).TotalMinutes
        if ($Vm.tags.onlineObservedAt) {
            $onlineObserved = [DateTimeOffset]::Parse([string]$Vm.tags.onlineObservedAt)
            $onlineObservedMin = [int]($onlineObserved - $registered).TotalMinutes
        }
    }
    $servedJob = ($null -ne $Vm.tags) -and ($null -ne $Vm.tags.registeredAt) -and (-not $runner)
    Write-Host "FLEETSTAT vm=$($Vm.name) pool=$(Get-VmPool -Vm $Vm) createdAt=$($Vm.created) ageMin=$(Get-VmAgeMinutes -Vm $Vm) bootMin=$bootMin onlineObservedMin=$onlineObservedMin servedJob=$servedJob reason=$Reason"
}

function Get-OrphanedNetworking {
    # Unattached NICs and instance public IPs matching the CI naming convention. The
    # filters mirror the janitor's own patterns (janitor-runbook.ps1:255, :265) so both
    # sweepers agree on what counts as garbage.
    #
    # JMESPath needs single quotes for string literals and literal backticks around null.
    # PowerShell therefore escapes each query backtick by doubling it in the string.
    $nicQuery = "[?virtualMachine==``null`` && contains(name, 'Nic-')].name"
    $pipQuery = "[?ipConfiguration==``null`` && starts_with(name, 'instancepublicip-')].name"
    $nics = @(Invoke-AzJson -Arguments @(
            "network", "nic", "list", "--resource-group", $resourceGroup,
            "--query", $nicQuery
        ) -Operation "list orphaned NICs")
    $pips = @(Invoke-AzJson -Arguments @(
            "network", "public-ip", "list", "--resource-group", $resourceGroup,
            "--query", $pipQuery
        ) -Operation "list orphaned public IPs")
    [pscustomobject]@{
        Nics = $nics
        Pips = $pips
    }
}

function Remove-OrphanedNetworking {
    param($Snapshot)
    # The VM delete leaves its NIC and instance public IP behind; the 6-hourly janitor
    # was the only thing reaping them, and they bill the whole time. July: 1661 IP-hours
    # against 949 VM-hours.
    #
    # Only resources orphaned BOTH at the start of this run and now are deleted. A NIC
    # created by this run's vmss scale reads virtualMachine==null for a moment before
    # its VM attaches, and deleting it would break that VM's creation.
    $current = Get-OrphanedNetworking
    $staleNics = @($current.Nics | Where-Object { $PSItem -in $Snapshot.Nics })
    $stalePips = @($current.Pips | Where-Object { $PSItem -in $Snapshot.Pips })
    foreach ($nicName in $staleNics) {
        $splatDeleteNic = @{
            Tool      = "az"
            Arguments = @(
                "network", "nic", "delete", "--resource-group", $resourceGroup,
                "--name", $nicName, "--only-show-errors", "--output", "none"
            )
            Operation = "delete orphaned NIC $nicName"
        }
        $null = Invoke-NativeText @splatDeleteNic
    }
    # NICs first: a public IP still bound to a NIC cannot be deleted.
    foreach ($pipName in $stalePips) {
        $splatDeletePip = @{
            Tool      = "az"
            Arguments = @(
                "network", "public-ip", "delete", "--resource-group", $resourceGroup,
                "--name", $pipName, "--only-show-errors", "--output", "none"
            )
            Operation = "delete orphaned public IP $pipName"
        }
        $null = Invoke-NativeText @splatDeletePip
    }
    Write-Host "reaped orphans: nics=$($staleNics.Count) pips=$($stalePips.Count)"
}

function Get-PoolJobDemand {
    param([object[]]$WorkflowRuns)
    # I/O only -- eligibility, matrix-state detection and the demand transform live in
    # runner-policy.ps1, where they are unit tested. Rejected runs are filtered before
    # I/O so an unmarked push cannot spend an API call or inflate an already-hot lane.
    $eligibleLiveRuns = @($WorkflowRuns | Where-Object {
            $splatEligibility = @{
                Run            = $PSItem
                OptInPushUsers = $optInPushUsers
                Marker         = $ciMarker
            }
            [string]$PSItem.status -ne "completed" -and (Test-CiRunEligible @splatEligibility)
        })
    $jobsByRun = @{ }
    foreach ($run in $eligibleLiveRuns) {
        $jobResponse = Invoke-GhJson -Arguments @(
            "repos/$repo/actions/runs/$($run.id)/jobs?per_page=100"
        ) -Operation "read jobs for run $($run.id)"
        $jobsByRun[[string]$run.id] = @($jobResponse.jobs)
    }

    $splatDemand = @{
        WorkflowRuns    = $eligibleLiveRuns
        JobsByRun       = $jobsByRun
        Maintainers     = $maintainers
        OptInPushUsers  = $optInPushUsers
        Marker          = $ciMarker
        MaintainerCount = $maintainerCount
        CommunityCount  = $communityCount
    }
    Get-PoolJobDemandFromRuns @splatDemand
}

function Get-RunnerDemand {
    $events = @(Invoke-GhJson -Arguments @("repos/$repo/events?per_page=100") -Operation "read repository activity")
    $runResponse = Invoke-GhJson -Arguments @(
        "repos/$repo/actions/workflows/ci-azure.yml/runs?per_page=100"
    ) -Operation "read CI build queue"
    $workflowRuns = @($runResponse.workflow_runs)
    $now = [DateTimeOffset]::UtcNow
    $poolJobDemand = Get-PoolJobDemand -WorkflowRuns $workflowRuns
    Write-Host "pending jobs: $(($poolJobDemand.GetEnumerator() | ForEach-Object { "$($PSItem.Key)=$($PSItem.Value)" }) -join ", ")"
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
        PoolJobDemand           = $poolJobDemand
        WarmFloor               = $warmFloor
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
        # Only the first successful registration is stamped. Register-PoolVms re-probes
        # any VM whose runner is still offline (:462), and bootstrap short-circuits with
        # "runner already configured" (:33-36) -- which is also exit 0. Re-stamping there
        # would overwrite the real registration time for exactly the VMs still inside the
        # boot window, i.e. the whole population bootMin is meant to measure.
        if ($result.Output -notmatch "already configured" -and $result.Output -notmatch "SPENT-VM") {
            Set-VmRegisteredAt -VmName $result.VmName
        }
        if ($result.Output -match "SPENT-VM") {
            $vm = @($State.Vms | Where-Object name -EQ $result.VmName | Select-Object -First 1)[0]
            Remove-FleetVm -State $State -Vm $vm -Reason "ephemeral runner already served a job"
        }
    }
}

function Invoke-VmssCapacityPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 35)]
        [int]$NominalCapacity,
        [Parameter(Mandatory)]
        [ValidateRange(0, 35)]
        [int]$ActualCapacity,
        [Parameter(Mandatory)]
        [ValidateRange(0, 35)]
        [int]$TargetCapacity,
        [Parameter(Mandatory)]
        [int]$TransitionBusy,
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$Vmss
    )

    Write-Host "capacity=$NominalCapacity actual_capacity=$ActualCapacity target=$TargetCapacity transition_busy=$TransitionBusy"
    $splatCapacity = @{
        NominalCapacity = $NominalCapacity
        ActualCapacity  = $ActualCapacity
        TargetCapacity  = $TargetCapacity
    }
    foreach ($newCapacity in Get-VmssCapacityPlan @splatCapacity) {
        $scaleArguments = @(
            "vmss", "scale", "--resource-group", $ResourceGroup, "--name", $Vmss,
            "--new-capacity", "$newCapacity", "--only-show-errors", "--output", "none"
        )
        $operation = "normalize VMSS capacity to $newCapacity"
        if ($newCapacity -gt $ActualCapacity) {
            $scaleArguments += "--no-wait"
            $operation = "scale VMSS to $newCapacity"
        }
        $splatScale = @{
            Tool      = "az"
            Arguments = $scaleArguments
            Operation = $operation
        }
        $null = Invoke-NativeText @splatScale
    }
    if ($ActualCapacity -lt $TargetCapacity) {
        foreach ($attempt in 1..15) {
            Start-Sleep -Seconds 20
            $state = Get-FleetState
            $notReady = @($state.Vms | Where-Object provisioning -NE "Succeeded").Count
            if ($state.Vms.Count -ge $TargetCapacity -and $notReady -eq 0) {
                break
            }
            Write-Host "provisioning check $attempt of 15: vms=$($state.Vms.Count)/$TargetCapacity not_ready=$notReady"
        }
    }
}

try {
    $demand = Get-RunnerDemand
    $orphanSnapshot = Get-OrphanedNetworking
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
    Set-VmOnlineObservedAt -State $state -Vms $state.Vms

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
    $actualCapacity = $state.Vms.Count
    $splatCapacity = @{
        NominalCapacity = $capacity
        ActualCapacity  = $actualCapacity
        TargetCapacity  = $target
        TransitionBusy  = $transitionBusy
        ResourceGroup   = $resourceGroup
        Vmss            = $vmss
    }
    Invoke-VmssCapacityPlan @splatCapacity

    $state = Get-FleetState
    Assign-UnallocatedVms -State $state -Desired $desired
    $state = Get-FleetState
    Register-PoolVms -State $state -Desired $desired
    $state = Get-FleetState
    Set-VmOnlineObservedAt -State $state -Vms $state.Vms
    foreach ($pool in $desired.Keys) {
        $poolVms = @($state.Vms | Where-Object { (Get-VmPool -Vm $PSItem) -eq $pool })
        $poolRunners = @($state.Runners | Where-Object { (Get-RunnerPool -Runner $PSItem) -eq $pool })
        $online = @($poolRunners | Where-Object status -EQ "online").Count
        $busy = @($poolRunners | Where-Object busy).Count
        Write-Host "pool=$pool desired=$($desired[$pool]) vms=$($poolVms.Count) online=$online busy=$busy"
    }

    Remove-OrphanedNetworking -Snapshot $orphanSnapshot
} catch [TransientFleetException] {
    Write-Warning "$($PSItem.Exception.Message) No further fleet changes will be attempted; a job-completion nudge or scheduled reconcile will retry."
    exit 0
}
