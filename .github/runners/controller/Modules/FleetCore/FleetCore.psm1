<#
.SYNOPSIS
    Reconciles the AppVeyor-style GitHub Actions worker pools on the Azure VMSS.

.DESCRIPTION
    Maintains four logical pools on one Flexible VMSS. Individual VMs retain their
    pool assignment in the runnerPool tag and register with a matching GitHub runner
    label. Runner agents are ephemeral; a VM is deleted after its single job and its
    pool slot is replaced from the golden image.

    External control-plane calls are retried three times. Exhausted control-plane
    failures throw TransientFleetException so the pass can bail out green without
    making scaling decisions from incomplete state. Logic errors still fail normally.

    This is the port of reconcile-runner-fleet.ps1 from the gh/az CLIs to raw REST so
    it can run inside an Azure Function, which has neither binary. The pool logic is
    unchanged and still lives in runner-policy.ps1, dot-sourced beside this file by
    deploy-controller.ps1.

.NOTES
    Author: the dbatools team + Claude
#>

class TransientFleetException : System.Exception {
    TransientFleetException([string]$message) : base($message) { }
}

$script:Fleet = $null

function Resolve-FleetFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    # Deployed, deploy-controller.ps1 stages everything beside this module. In the repo
    # the same files stay at .github/runners/ and .github/runners/controller/, where the
    # mirror tests and runner-scale-up.yml expect them. Searching both layouts is what
    # lets the tests import this module straight from a checkout with no staging step.
    $roots = @(
        $PSScriptRoot,
        (Join-Path -Path $PSScriptRoot -ChildPath "../.."),
        (Join-Path -Path $PSScriptRoot -ChildPath "../../..")
    )
    foreach ($root in $roots) {
        $candidate = Join-Path -Path $root -ChildPath $Name
        if (Test-Path -Path $candidate) {
            return (Resolve-Path -Path $candidate).Path
        }
    }
    throw "Cannot find $Name beside FleetCore or in the repo layout above it"
}

. (Resolve-FleetFile -Name "runner-policy.ps1")

function New-TransientFleetException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    New-Object -TypeName TransientFleetException -ArgumentList $Message
}

function Get-FleetSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,
        [Parameter(Mandatory)]
        [string]$Name
    )

    # An app setting of the same name wins over the committed default. That is the
    # emergency lever -- change one number in the portal, no redeploy, no PR.
    $override = [Environment]::GetEnvironmentVariable($Name)
    if ($override) {
        return $override
    }
    $Config[$Name]
}

function Get-FleetConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    if (-not $ConfigPath) {
        $ConfigPath = Resolve-FleetFile -Name "fleet-config.psd1"
    }
    $config = Import-PowerShellDataFile -Path $ConfigPath
    $resolved = @{ }
    foreach ($key in $config.Keys) {
        $resolved[$key] = Get-FleetSetting -Config $config -Name $key
    }
    $resolved
}

function Initialize-FleetContext {
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    $config = Get-FleetConfig -ConfigPath $ConfigPath
    $requiredSettings = @(
        "REPO",
        "RG",
        "VMSS",
        "SUBSCRIPTION_ID",
        "GITHUB_APP_ID",
        "GITHUB_INSTALLATION_ID",
        "GITHUB_APP_PRIVATE_KEY"
    )
    $missingSettings = @($requiredSettings | Where-Object { -not [Environment]::GetEnvironmentVariable($PSItem) })
    if ($missingSettings) {
        throw "Missing required fleet settings: $($missingSettings -join ", ")"
    }

    # Fails closed, and refuses anything but the two words. A missing or misspelled DRY_RUN
    # would otherwise read as "not dry" and let a controller that was only supposed to be
    # shadowing delete real runners. In the old workflow this arrived from a dispatch input
    # that could not be absent; here it is an app setting one typo away from armed.
    $dryRunSetting = [string]$env:DRY_RUN
    if ($dryRunSetting -notin @("true", "false")) {
        throw "DRY_RUN must be exactly `"true`" or `"false`"; got `"$dryRunSetting`""
    }

    $bootstrapPath = Resolve-FleetFile -Name "bootstrap-runner.ps1"

    $script:Fleet = @{
        Repo                    = $env:REPO
        ResourceGroup           = $env:RG
        Vmss                    = $env:VMSS
        SubscriptionId          = $env:SUBSCRIPTION_ID
        RunnerLabel             = [string]$config["RUNNER_LABEL"]
        PoolLabelPrefix         = [string]$config["POOL_LABEL_PREFIX"]
        CiWorkflow              = [string]$config["CI_WORKFLOW"]
        CommunityCount          = [int]$config["COMMUNITY_COUNT"]
        MaintainerCount         = [int]$config["BOOST_COUNT"]
        MaintainerWindowMinutes = [int]$config["BOOST_HOURS"] * 60
        CommunityGraceMinutes   = [int]$config["COMMUNITY_GRACE_MINUTES"]
        MaxRunners              = [int]$config["MAX_RUNNERS"]
        WarmFloor               = [int]$config["WARM_FLOOR"]
        Maintainers             = @([string]$config["BOOST_USERS"] -split "\s+" | Where-Object { $PSItem })
        OptInPushUsers          = @([string]$config["OPT_IN_PUSH_USERS"] -split "\s+" | Where-Object { $PSItem })
        CiMarker                = [string]$config["CI_MARKER"]
        BootstrapPath           = $bootstrapPath
        DryRun                  = $dryRunSetting -eq "true"
        DeletedVms              = New-Object -TypeName "System.Collections.Generic.HashSet[string]" -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        ArmToken                = $null
        ArmTokenExpiry          = [DateTimeOffset]::MinValue
        GitHubToken             = $null
    }
    $script:Fleet
}

function Test-FleetDryRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Decision
    )

    if (-not $script:Fleet.DryRun) {
        return $false
    }
    Write-Host "DECISION $Decision"
    $true
}

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
                throw (New-TransientFleetException -Message "$Operation failed after 3 attempts. $($PSItem.Exception.Message)")
            }
            Write-Warning "$Operation attempt $attempt of 3 failed; retrying. $($PSItem.Exception.Message)"
            Start-Sleep -Seconds (3 * $attempt)
        }
    }
}

function Get-HttpErrorText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ErrorRecord
    )

    # The retry wrapper's message is what Remove-FleetVm pattern-matches on to spot a
    # runner that took a job mid-delete, so the response body has to survive into it.
    # Invoke-RestMethod keeps the body in ErrorDetails, not in the exception message.
    $detail = [string]$ErrorRecord.ErrorDetails.Message
    if ($detail) {
        return "$($ErrorRecord.Exception.Message) $detail"
    }
    [string]$ErrorRecord.Exception.Message
}

function Get-ArmToken {
    [CmdletBinding()]
    param()

    if ($script:Fleet.ArmToken -and [DateTimeOffset]::UtcNow -lt $script:Fleet.ArmTokenExpiry) {
        return $script:Fleet.ArmToken
    }
    # Straight to the managed identity endpoint rather than Connect-AzAccount: Flex
    # Consumption caps app init at 30 seconds and has no managed dependencies, so
    # importing Az.Accounts would be both slow and an extra thing to ship. Token
    # strings are also safe to hand to ForEach-Object -Parallel; an Az context is not.
    $endpoint = $env:IDENTITY_ENDPOINT
    $identityHeader = $env:IDENTITY_HEADER
    if (-not $endpoint -or -not $identityHeader) {
        throw "No managed identity endpoint; the Function App needs a system-assigned identity"
    }
    $splatToken = @{
        Uri        = "$($endpoint)?resource=https://management.azure.com/&api-version=2019-08-01"
        Headers    = @{ "X-IDENTITY-HEADER" = $identityHeader }
        TimeoutSec = 30
    }
    $response = Invoke-WithRetry -Operation "acquire ARM token" -Action {
        Invoke-RestMethod @splatToken
    }
    $script:Fleet.ArmToken = $response.access_token
    $expiry = [DateTimeOffset]::UtcNow.AddMinutes(45)
    if ($response.expires_on) {
        $expiresOn = [string]$response.expires_on
        [long]$parsedSeconds = 0
        if ([long]::TryParse($expiresOn, [ref]$parsedSeconds)) {
            $expiry = [DateTimeOffset]::FromUnixTimeSeconds($parsedSeconds)
        } else {
            $expiry = [DateTimeOffset]::Parse($expiresOn)
        }
    }
    $script:Fleet.ArmTokenExpiry = $expiry.AddMinutes(-5)
    $script:Fleet.ArmToken
}

function Get-GitHubToken {
    [CmdletBinding()]
    param()

    if (-not $script:Fleet.GitHubToken) {
        $splatInstallation = @{
            AppId          = $env:GITHUB_APP_ID
            InstallationId = $env:GITHUB_INSTALLATION_ID
            PrivateKeyPem  = $env:GITHUB_APP_PRIVATE_KEY
        }
        $script:Fleet.GitHubToken = Invoke-WithRetry -Operation "mint GitHub installation token" -Action {
            Get-GitHubInstallationToken @splatInstallation
        }
    }
    $script:Fleet.GitHubToken
}

function Invoke-GhJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$Method = "Get",
        $Body,
        [Parameter(Mandatory)]
        [string]$Operation
    )

    $uri = $Path
    if ($uri -notmatch "^https://") {
        $uri = "https://api.github.com/$($Path.TrimStart("/"))"
    }
    $splatRequest = @{
        Method     = $Method
        Uri        = $uri
        Headers    = @{
            Accept                 = "application/vnd.github+json"
            Authorization          = "Bearer $(Get-GitHubToken)"
            "X-GitHub-Api-Version" = "2022-11-28"
            "User-Agent"           = "dbatools-fleet-controller"
        }
        TimeoutSec = 60
    }
    if ($null -ne $Body) {
        $splatRequest["Body"] = ($Body | ConvertTo-Json -Depth 6)
        $splatRequest["ContentType"] = "application/json"
    }
    Invoke-WithRetry -Operation $Operation -Action {
        try {
            Invoke-RestMethod @splatRequest
        } catch {
            throw (Get-HttpErrorText -ErrorRecord $PSItem)
        }
    }
}

function Invoke-ArmWeb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$Method = "Get",
        $Body,
        [Parameter(Mandatory)]
        [string]$Operation
    )

    $uri = $Path
    if ($uri -notmatch "^https://") {
        $uri = "https://management.azure.com$Path"
    }
    $splatRequest = @{
        Method     = $Method
        Uri        = $uri
        Headers    = @{ Authorization = "Bearer $(Get-ArmToken)" }
        TimeoutSec = 120
    }
    if ($null -ne $Body) {
        $splatRequest["Body"] = ($Body | ConvertTo-Json -Depth 10)
        $splatRequest["ContentType"] = "application/json"
    }
    Invoke-WithRetry -Operation $Operation -Action {
        try {
            Invoke-WebRequest @splatRequest -UseBasicParsing
        } catch {
            throw (Get-HttpErrorText -ErrorRecord $PSItem)
        }
    }
}

function Invoke-ArmJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$Method = "Get",
        $Body,
        [Parameter(Mandatory)]
        [string]$Operation
    )

    $splatArm = @{
        Path      = $Path
        Method    = $Method
        Body      = $Body
        Operation = $Operation
    }
    $response = Invoke-ArmWeb @splatArm
    if (-not $response.Content) {
        return $null
    }
    $response.Content | ConvertFrom-Json -Depth 20
}

function Invoke-ArmList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Operation
    )

    # ARM list operations paginate at the service's discretion, and reading only the
    # first page silently shrinks the fleet inventory -- VMs past the boundary would
    # never be counted or reaped. The az CLI followed nextLink for us; raw REST does
    # not, so every list call in this module has to come through here.
    $next = $Path
    while ($next) {
        $splatPage = @{
            Path      = $next
            Operation = $Operation
        }
        $page = Invoke-ArmJson @splatPage
        if (-not $page) {
            break
        }
        $page.value
        $next = [string]$page.nextLink
    }
}

function Get-ResponseHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Response,
        [Parameter(Mandatory)]
        [string]$Name
    )

    $value = $Response.Headers[$Name]
    if (-not $value) {
        return $null
    }
    # PowerShell 7 gives every response header as a collection, even single-valued ones.
    @($value)[0]
}

function Wait-ArmOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Response,
        [Parameter(Mandatory)]
        [string]$Operation,
        [int]$TimeoutMinutes = 20
    )

    if ([int]$Response.StatusCode -ne 202) {
        if ($Response.Content) {
            return ($Response.Content | ConvertFrom-Json -Depth 20)
        }
        return $null
    }

    $asyncUri = Get-ResponseHeader -Response $Response -Name "Azure-AsyncOperation"
    $locationUri = Get-ResponseHeader -Response $Response -Name "Location"
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes($TimeoutMinutes)
    $pollSeconds = 5
    $retryAfter = Get-ResponseHeader -Response $Response -Name "Retry-After"
    if ($retryAfter -and [int]$retryAfter -gt 0) {
        $pollSeconds = [int]$retryAfter
    }

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds $pollSeconds
        if ($asyncUri) {
            $status = Invoke-ArmJson -Path $asyncUri -Operation "poll $Operation"
            if ([string]$status.status -in @("Failed", "Canceled")) {
                throw (New-TransientFleetException -Message "$Operation ended $($status.status). $($status.error.message)")
            }
            if ([string]$status.status -ne "Succeeded") {
                continue
            }
            if (-not $locationUri) {
                return $null
            }
            return (Invoke-ArmJson -Path $locationUri -Operation "read result of $Operation")
        }
        if (-not $locationUri) {
            return $null
        }
        $poll = Invoke-ArmWeb -Path $locationUri -Operation "poll $Operation"
        if ([int]$poll.StatusCode -eq 202) {
            continue
        }
        if ($poll.Content) {
            return ($poll.Content | ConvertFrom-Json -Depth 20)
        }
        return $null
    }
    throw (New-TransientFleetException -Message "$Operation did not finish within $TimeoutMinutes minutes")
}

function Invoke-ArmOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Method,
        $Body,
        [Parameter(Mandatory)]
        [string]$Operation,
        [int]$TimeoutMinutes = 20
    )

    $splatArm = @{
        Path      = $Path
        Method    = $Method
        Body      = $Body
        Operation = $Operation
    }
    $response = Invoke-ArmWeb @splatArm
    $splatWait = @{
        Response       = $response
        Operation      = $Operation
        TimeoutMinutes = $TimeoutMinutes
    }
    Wait-ArmOperation @splatWait
}

function Get-RunnerPool {
    param($Runner)
    if (-not $Runner) {
        return $null
    }
    $label = @($Runner.labels.name | Where-Object { $PSItem -like "$($script:Fleet.PoolLabelPrefix)*" } | Select-Object -First 1)
    if (-not $label) {
        return $null
    }
    $label[0].Substring($script:Fleet.PoolLabelPrefix.Length)
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
    $splatRunners = @{
        Path      = "repos/$($script:Fleet.Repo)/actions/runners?per_page=100"
        Operation = "list GitHub runners"
    }
    $runnerResponse = Invoke-GhJson @splatRunners
    $runners = @($runnerResponse.runners | Where-Object { $PSItem.labels.name -contains $script:Fleet.RunnerLabel })
    # One list call, not the CLI's --show-details fan-out: the projection below is
    # everything the fleet logic reads, and powerState was only ever projected, never
    # used. Skipping the per-VM instanceView removes N round trips from every pass.
    $splatVms = @{
        Path      = "/subscriptions/$($script:Fleet.SubscriptionId)/resourceGroups/$($script:Fleet.ResourceGroup)/providers/Microsoft.Compute/virtualMachines?api-version=2024-07-01"
        Operation = "list Azure runner VMs"
    }
    $vmResponse = @(Invoke-ArmList @splatVms)
    $vms = @(
        $vmResponse |
            Where-Object { [string]$PSItem.name -like "$($script:Fleet.Vmss)_*" } |
            ForEach-Object {
                [pscustomobject]@{
                    name         = [string]$PSItem.name
                    id           = [string]$PSItem.id
                    created      = [string]$PSItem.properties.timeCreated
                    provisioning = [string]$PSItem.properties.provisioningState
                    tags         = $PSItem.tags
                }
            }
    )
    [pscustomobject]@{ Runners = $runners; Vms = $vms }
}

function Get-RunnerForVm {
    param($State, [string]$VmName)
    @($State.Runners | Where-Object name -EQ $VmName | Select-Object -First 1)[0]
}

function Set-VmTag {
    param([string]$VmId, [string]$VmName, [hashtable]$Tags, [string]$Operation)
    # Use the dedicated tag API. `az vm update --set tags.*` can invoke Azure's
    # unrelated zone-movement validation and reject otherwise valid VM tag changes.
    $body = @{
        operation  = "Merge"
        properties = @{ tags = $Tags }
    }
    $splatTag = @{
        Path      = "$VmId/providers/Microsoft.Resources/tags/default?api-version=2024-03-01"
        Method    = "Patch"
        Body      = $body
        Operation = $Operation
    }
    $null = Invoke-ArmJson @splatTag
}

function Set-VmPool {
    param($Vm, [string]$Pool)
    if (Test-FleetDryRun -Decision "tag vm=$($Vm.name) pool=$Pool") {
        return
    }
    $splatPoolTag = @{
        VmId      = $Vm.id
        VmName    = $Vm.name
        Tags      = @{ runnerPool = $Pool }
        Operation = "tag $($Vm.name) for pool $Pool"
    }
    Set-VmTag @splatPoolTag
    Write-Host "assigned $($Vm.name) to pool $Pool"
}

function Set-VmTimestampTag {
    param(
        $Vm,
        [string]$TagName
    )
    $stamp = [DateTimeOffset]::UtcNow.ToString("o")
    if (Test-FleetDryRun -Decision "stamp vm=$($Vm.name) tag=$TagName") {
        return
    }
    $splatStampTag = @{
        VmId      = $Vm.id
        VmName    = $Vm.name
        Tags      = @{ $TagName = $stamp }
        Operation = "stamp $($Vm.name) $TagName"
    }
    Set-VmTag @splatStampTag
}

function Set-VmRegisteredAt {
    param($Vm)
    # Records when bootstrap finished registering the runner. Paired with the VM's
    # creation time in Remove-FleetVm, this separates boot overhead from hot-idle
    # time -- the two are indistinguishable in Azure cost data alone.
    Set-VmTimestampTag -Vm $Vm -TagName "registeredAt"
}

function Set-VmOnlineObservedAt {
    param($State, $Vms)
    # Records when the controller first observes a runner online. This is an upper bound
    # on listener startup, not its exact timestamp: observation is delayed by up to the
    # gap between passes. It still separates startup from longer hot-idle waiting
    # without granting the runner an Azure identity.
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
        Set-VmTimestampTag -Vm $vm -TagName "onlineObservedAt"
    }
}

function Remove-FleetVm {
    param($State, $Vm, [string]$Reason)
    if (-not $script:Fleet.DeletedVms.Add($Vm.name)) {
        return
    }
    $runner = Get-RunnerForVm -State $State -VmName $Vm.name
    if ($runner -and $runner.busy) {
        $null = $script:Fleet.DeletedVms.Remove($Vm.name)
        Write-Host "preserving busy $($Vm.name) despite: $Reason"
        return
    }
    Write-Host "deleting $($Vm.name) -- $Reason"
    if (-not $script:Fleet.DryRun) {
        if ($runner) {
            try {
                $splatRunnerDelete = @{
                    Path      = "repos/$($script:Fleet.Repo)/actions/runners/$($runner.id)"
                    Method    = "Delete"
                    Operation = "remove runner record $($runner.name)"
                }
                $null = Invoke-GhJson @splatRunnerDelete
            } catch [TransientFleetException] {
                if ($PSItem.Exception.Message -notmatch "currently running a job") {
                    throw
                }
                $null = $script:Fleet.DeletedVms.Remove($Vm.name)
                Write-Host "preserving $($Vm.name); it accepted a job during the deletion check"
                return
            }
        }
        # The CLI waited for the delete; so does this, because FLEETSTAT is emitted
        # after it and the pass re-reads inventory expecting the VM to be gone.
        $splatVmDelete = @{
            Path      = "$($Vm.id)?api-version=2024-07-01"
            Method    = "Delete"
            Operation = "delete VM $($Vm.name)"
        }
        $null = Invoke-ArmOperation @splatVmDelete
    } else {
        Write-Host "DECISION delete vm=$($Vm.name) reason=$Reason"
    }
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
    $splatNics = @{
        Path      = "/subscriptions/$($script:Fleet.SubscriptionId)/resourceGroups/$($script:Fleet.ResourceGroup)/providers/Microsoft.Network/networkInterfaces?api-version=2024-05-01"
        Operation = "list orphaned NICs"
    }
    $nicResponse = @(Invoke-ArmList @splatNics)
    $nics = @(
        $nicResponse |
            Where-Object { -not $PSItem.properties.virtualMachine -and [string]$PSItem.name -like "*Nic-*" } |
            ForEach-Object { [string]$PSItem.name }
    )
    $splatPips = @{
        Path      = "/subscriptions/$($script:Fleet.SubscriptionId)/resourceGroups/$($script:Fleet.ResourceGroup)/providers/Microsoft.Network/publicIPAddresses?api-version=2024-05-01"
        Operation = "list orphaned public IPs"
    }
    $pipResponse = @(Invoke-ArmList @splatPips)
    $pips = @(
        $pipResponse |
            Where-Object { -not $PSItem.properties.ipConfiguration -and [string]$PSItem.name -like "instancepublicip-*" } |
            ForEach-Object { [string]$PSItem.name }
    )
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
    $resourceBase = "/subscriptions/$($script:Fleet.SubscriptionId)/resourceGroups/$($script:Fleet.ResourceGroup)/providers/Microsoft.Network"
    foreach ($nicName in $staleNics) {
        if (Test-FleetDryRun -Decision "reap nic=$nicName") {
            continue
        }
        $splatDeleteNic = @{
            Path      = "$resourceBase/networkInterfaces/$nicName`?api-version=2024-05-01"
            Method    = "Delete"
            Operation = "delete orphaned NIC $nicName"
        }
        $null = Invoke-ArmOperation @splatDeleteNic
    }
    # NICs first: a public IP still bound to a NIC cannot be deleted.
    foreach ($pipName in $stalePips) {
        if (Test-FleetDryRun -Decision "reap pip=$pipName") {
            continue
        }
        $splatDeletePip = @{
            Path      = "$resourceBase/publicIPAddresses/$pipName`?api-version=2024-05-01"
            Method    = "Delete"
            Operation = "delete orphaned public IP $pipName"
        }
        $null = Invoke-ArmOperation @splatDeletePip
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
                OptInPushUsers = $script:Fleet.OptInPushUsers
                Marker         = $script:Fleet.CiMarker
            }
            [string]$PSItem.status -ne "completed" -and (Test-CiRunEligible @splatEligibility)
        })
    $jobsByRun = @{ }
    foreach ($run in $eligibleLiveRuns) {
        $splatJobs = @{
            Path      = "repos/$($script:Fleet.Repo)/actions/runs/$($run.id)/jobs?per_page=100"
            Operation = "read jobs for run $($run.id)"
        }
        $jobResponse = Invoke-GhJson @splatJobs
        $jobsByRun[[string]$run.id] = @($jobResponse.jobs)
    }

    $splatDemand = @{
        WorkflowRuns    = $eligibleLiveRuns
        JobsByRun       = $jobsByRun
        Maintainers     = $script:Fleet.Maintainers
        OptInPushUsers  = $script:Fleet.OptInPushUsers
        Marker          = $script:Fleet.CiMarker
        MaintainerCount = $script:Fleet.MaintainerCount
        CommunityCount  = $script:Fleet.CommunityCount
    }
    Get-PoolJobDemandFromRuns @splatDemand
}

function Confirm-DirectTrigger {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Actor = "",
        [AllowEmptyString()]
        [string]$Sha = "",
        [AllowEmptyString()]
        [string]$Ref = ""
    )

    $empty = [pscustomobject]@{ Actor = ""; Message = ""; Sha = ""; Ref = "" }
    if (-not $Actor -or -not $Sha -or -not $Ref) {
        return $empty
    }
    # The all-zeros sha is git's null object -- a branch deletion's "after". Get-FleetNudge
    # already drops those deliveries; this catches one arriving any other way before it
    # burns three corroboration retries on a guaranteed 422.
    if ($Sha -match "^0+$") {
        Write-Warning "Trigger sha $Sha is the null object; converging from repository activity instead"
        return $empty
    }

    # A webhook body is a hint about where to look, never the fact itself. The HMAC
    # proves a delivery is authentic but not that it is current, so a captured delivery
    # replayed later would otherwise heat a pool or dispatch an old commit. Asking
    # GitHub for the ref's head settles that: a replay names a SHA that is no longer
    # the head and gets dropped, and the sha and message handed downstream come from
    # the API response rather than from the request body.
    # Branches only. A push webhook fires for tags too, and both the commits endpoint below
    # and workflow dispatch accept a tag ref, so without this a maintainer cutting a release
    # tag would heat a lane and dispatch CI at the tag. Stripping the prefix without first
    # requiring it also let refs/tags/x through as the "branch" refs/tags/x.
    if ($Ref -notlike "refs/heads/*") {
        Write-Warning "Trigger ref $Ref is not a branch; converging from repository activity instead"
        return $empty
    }
    $branch = $Ref -replace "^refs/heads/", ""
    # Conservative because this value reaches a REST path. Real branch names here are
    # well inside it, and anything stranger is dropped rather than escaped. The explicit
    # ".." check is the point of the whole test: a plain character class still admits
    # refs/heads/../../etc, which .NET collapses into a request to a different endpoint.
    if ($branch -notmatch "^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$" -or $branch -match "\.\.") {
        Write-Warning "Trigger ref $Ref is not a plain branch name; converging from repository activity instead"
        return $empty
    }
    $splatHead = @{
        Path      = "repos/$($script:Fleet.Repo)/commits/$branch"
        Operation = "corroborate the trigger commit on $branch"
    }
    try {
        $head = Invoke-GhJson @splatHead
    } catch {
        Write-Warning "Could not corroborate the trigger on $branch; converging from repository activity instead. $($PSItem.Exception.Message)"
        return $empty
    }
    if ([string]$head.sha -ne $Sha) {
        Write-Host "trigger hint for $branch is stale (head is $([string]$head.sha)); converging from repository activity instead"
        return $empty
    }
    # The actor stays the one the signed delivery named. What the HMAC could not prove was
    # freshness, and the sha check above settles that; who pushed was never in doubt, because
    # the body is GitHub's own statement of it. head.author.login is a different person --
    # the commit AUTHOR -- whenever someone pushes work they did not write, and the
    # maintainer and opt-in lists are about the pusher. Attributing to the author would both
    # miss a maintainer pushing a contributor's commit and hand a maintainer lane to anyone
    # who pushes a maintainer-authored one.
    $headAuthor = [string]$head.author.login
    if ($headAuthor -and $headAuthor -ne $Actor) {
        Write-Host "trigger $Sha was authored by $headAuthor and pushed by $Actor; attributing to the pusher"
    }
    [pscustomobject]@{
        Actor   = $Actor
        Message = [string]$head.commit.message
        Sha     = [string]$head.sha
        Ref     = $Ref
    }
}

function Get-RunnerDemand {
    param(
        [AllowEmptyString()]
        [string]$DirectTriggerActor = "",
        [AllowEmptyString()]
        [string]$DirectTriggerSha = "",
        [AllowEmptyString()]
        [string]$DirectTriggerRef = ""
    )

    # No DirectTriggerMessage parameter on purpose: the marker test downstream decides
    # whether CI runs, so the message it reads has to be the one GitHub holds, not the
    # one the caller was handed.
    $DirectTriggerMessage = ""

    $splatConfirm = @{
        Actor = $DirectTriggerActor
        Sha   = $DirectTriggerSha
        Ref   = $DirectTriggerRef
    }
    $trigger = Confirm-DirectTrigger @splatConfirm
    $DirectTriggerActor = $trigger.Actor
    $DirectTriggerMessage = $trigger.Message
    $DirectTriggerSha = $trigger.Sha
    $DirectTriggerRef = $trigger.Ref

    $splatEvents = @{
        Path      = "repos/$($script:Fleet.Repo)/events?per_page=100"
        Operation = "read repository activity"
    }
    $events = @(Invoke-GhJson @splatEvents)
    $splatRuns = @{
        Path      = "repos/$($script:Fleet.Repo)/actions/workflows/$($script:Fleet.CiWorkflow)/runs?per_page=100"
        Operation = "read CI build queue"
    }
    $runResponse = Invoke-GhJson @splatRuns
    $workflowRuns = @($runResponse.workflow_runs)
    $now = [DateTimeOffset]::UtcNow
    $poolJobDemand = Get-PoolJobDemand -WorkflowRuns $workflowRuns
    Write-Host "pending jobs: $(($poolJobDemand.GetEnumerator() | ForEach-Object { "$($PSItem.Key)=$($PSItem.Value)" }) -join ", ")"
    $splatPolicy = @{
        Events                  = $events
        WorkflowRuns            = $workflowRuns
        Maintainers             = $script:Fleet.Maintainers
        OptInPushUsers          = $script:Fleet.OptInPushUsers
        MaintainerCount         = $script:Fleet.MaintainerCount
        MaintainerWindowMinutes = $script:Fleet.MaintainerWindowMinutes
        CommunityCount          = $script:Fleet.CommunityCount
        CommunityGraceMinutes   = $script:Fleet.CommunityGraceMinutes
        MaxRunners              = $script:Fleet.MaxRunners
        Marker                  = $script:Fleet.CiMarker
        Now                     = $now
        DirectTriggerActor      = $DirectTriggerActor
        DirectTriggerMessage    = $DirectTriggerMessage
        PoolJobDemand           = $poolJobDemand
        WarmFloor               = $script:Fleet.WarmFloor
    }
    $desired = Get-DesiredRunnerPools @splatPolicy

    $total = ($desired.Values | Measure-Object -Sum).Sum
    Write-Host "desired pools: $(($desired.GetEnumerator() | ForEach-Object { "$($PSItem.Key)=$($PSItem.Value)" }) -join ", ") total=$total"
    $splatDispatch = @{
        Events               = $events
        WorkflowRuns         = $workflowRuns
        OptInPushUsers       = $script:Fleet.OptInPushUsers
        Marker               = $script:Fleet.CiMarker
        Cutoff               = $now.AddMinutes(-$script:Fleet.MaintainerWindowMinutes)
        DirectTriggerActor   = $DirectTriggerActor
        DirectTriggerMessage = $DirectTriggerMessage
        DirectTriggerSha     = $DirectTriggerSha
        DirectTriggerRef     = $DirectTriggerRef
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

    if (Test-FleetDryRun -Decision "dispatch ci ref=$($Request.Ref) sha=$($Request.Sha) actor=$($Request.Actor)") {
        return
    }
    $body = @{
        ref    = $Request.Ref
        inputs = @{ message = $Request.Message; pool_user = $Request.Actor }
    }
    $splatDispatch = @{
        Path      = "repos/$($script:Fleet.Repo)/actions/workflows/$($script:Fleet.CiWorkflow)/dispatches"
        Method    = "Post"
        Body      = $body
        Operation = "dispatch marked CI for $($Request.Sha)"
    }
    $null = Invoke-GhJson @splatDispatch
    Write-Host "dispatched marked CI ref=$($Request.Ref) sha=$($Request.Sha)"
}

function Set-UnallocatedVmPool {
    param($State, $Desired)
    $available = New-Object -TypeName "System.Collections.Generic.Queue[object]"
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
            Set-VmPool -Vm $vm -Pool $pool
            $deficit--
        }
    }
}

function Invoke-VmRunCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArmToken,
        [Parameter(Mandatory)]
        [string]$VmResourceId,
        [Parameter(Mandatory)]
        # Mandatory on a [string[]] rejects the whole array when any element is an empty
        # string, and this one is a PowerShell file read line by line -- bootstrap-runner.ps1
        # has 16 blank lines. Every registration failed with "because it is an empty string"
        # until this attribute went on. An empty array and a null still fail, which is what
        # a missing or truncated bootstrap should do.
        [AllowEmptyString()]
        [string[]]$ScriptLines,
        [Parameter(Mandatory)]
        [object[]]$Parameters,
        [int]$TimeoutMinutes = 20
    )

    # Deliberately self-contained -- no module state, no helper calls. Register-PoolVms
    # injects this whole function into ForEach-Object -Parallel runspaces, which cannot
    # see anything from the module scope.
    $headers = @{ Authorization = "Bearer $ArmToken" }
    $body = @{
        commandId  = "RunPowerShellScript"
        script     = $ScriptLines
        parameters = $Parameters
    } | ConvertTo-Json -Depth 6
    $splatInvoke = @{
        Method      = "Post"
        Uri         = "https://management.azure.com$VmResourceId/runCommand?api-version=2024-07-01"
        Headers     = $headers
        Body        = $body
        ContentType = "application/json"
        TimeoutSec  = 120
    }
    $response = Invoke-WebRequest @splatInvoke -UseBasicParsing

    $result = $null
    if ([int]$response.StatusCode -ne 202) {
        if ($response.Content) {
            $result = $response.Content | ConvertFrom-Json -Depth 20
        }
    } else {
        $asyncUri = @($response.Headers["Azure-AsyncOperation"])[0]
        $locationUri = @($response.Headers["Location"])[0]
        $deadline = [DateTimeOffset]::UtcNow.AddMinutes($TimeoutMinutes)
        while ([DateTimeOffset]::UtcNow -lt $deadline) {
            Start-Sleep -Seconds 5
            if ($asyncUri) {
                $splatStatus = @{
                    Uri        = $asyncUri
                    Headers    = $headers
                    TimeoutSec = 60
                }
                $status = Invoke-RestMethod @splatStatus
                if ([string]$status.status -in @("Failed", "Canceled")) {
                    throw "run-command ended $($status.status). $($status.error.message)"
                }
                if ([string]$status.status -ne "Succeeded") {
                    continue
                }
            }
            if (-not $locationUri) {
                break
            }
            $splatPoll = @{
                Method     = "Get"
                Uri        = $locationUri
                Headers    = $headers
                TimeoutSec = 60
            }
            $poll = Invoke-WebRequest @splatPoll -UseBasicParsing
            if ([int]$poll.StatusCode -eq 202) {
                continue
            }
            if ($poll.Content) {
                $result = $poll.Content | ConvertFrom-Json -Depth 20
            }
            break
        }
        if (-not $result -and [DateTimeOffset]::UtcNow -ge $deadline) {
            throw "run-command did not finish within $TimeoutMinutes minutes"
        }
    }
    [string]@($result.value)[0].message
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
        # A VM that has not finished provisioning cannot take a RunCommand yet. Scale-out
        # no longer waits for readiness in-pass, so fresh instances land here mid-build;
        # they keep their pool tag and register on a later pass once Succeeded.
        if ($vm.provisioning -ne "Succeeded") {
            continue
        }
        $labels = "$($script:Fleet.RunnerLabel),$($script:Fleet.PoolLabelPrefix)$pool"
        if (Test-FleetDryRun -Decision "register vm=$($vm.name) labels=$labels") {
            continue
        }
        # Probe offline ephemeral runners too. The bootstrap distinguishes a VM that
        # is still starting from one whose runner already served its single job.
        $splatToken = @{
            Path      = "repos/$($script:Fleet.Repo)/actions/runners/registration-token"
            Method    = "Post"
            Operation = "mint registration token for $($vm.name)"
        }
        $tokenResponse = Invoke-GhJson @splatToken
        $tasks += [pscustomobject]@{
            Vm     = $vm
            VmName = $vm.name
            Token  = $tokenResponse.token
            Labels = $labels
        }
    }
    if (-not $tasks) {
        return
    }

    Write-Host "registering $($tasks.Count) pool runner(s)"
    $armToken = Get-ArmToken
    $bootstrapLines = @(Get-Content -Path $script:Fleet.BootstrapPath)
    $runCommandDefinition = ${function:Invoke-VmRunCommand}.ToString()
    $results = $tasks | ForEach-Object -Parallel {
        ${function:Invoke-VmRunCommand} = $using:runCommandDefinition
        # Bind the task to its own name before the try. Inside catch, $PSItem is the
        # ErrorRecord, not the pipeline item, so reading $PSItem.VmName there yields
        # $null -- which silently strips the identity off every failed registration
        # and, on SPENT-VM, hands Remove-FleetVm a null VM. The CLI original had no
        # try/catch (it read $LASTEXITCODE) and so never hit this.
        $task = $PSItem
        $parameters = @(
            @{ name = "Token"; value = $task.Token },
            @{ name = "RunnerName"; value = $task.VmName },
            @{ name = "Labels"; value = $task.Labels }
        )
        $splatRunCommand = @{
            ArmToken     = $using:armToken
            VmResourceId = $task.Vm.id
            ScriptLines  = $using:bootstrapLines
            Parameters   = $parameters
        }
        $result = $null
        foreach ($attempt in 1..3) {
            try {
                $outputText = Invoke-VmRunCommand @splatRunCommand
                $result = [pscustomobject]@{ VmName = $task.VmName; Vm = $task.Vm; Succeeded = $true; Output = $outputText }
                break
            } catch {
                $outputText = $PSItem.Exception.Message
                # A bootstrap that reports SPENT-VM has done its job even if the
                # transport around it stumbled; the caller still needs to see it.
                if ($outputText -match "SPENT-VM") {
                    $result = [pscustomobject]@{ VmName = $task.VmName; Vm = $task.Vm; Succeeded = $true; Output = $outputText }
                    break
                }
                if ($attempt -lt 3) {
                    Start-Sleep -Seconds (3 * $attempt)
                } else {
                    $result = [pscustomobject]@{ VmName = $task.VmName; Vm = $task.Vm; Succeeded = $false; Output = $outputText }
                }
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
            Set-VmRegisteredAt -Vm $result.Vm
        }
        if ($result.Output -match "SPENT-VM") {
            $vm = @($State.Vms | Where-Object name -EQ $result.VmName | Select-Object -First 1)[0]
            Remove-FleetVm -State $State -Vm $vm -Reason "ephemeral runner already served a job"
        }
    }
}

function Set-FleetHeartbeat {
    [CmdletBinding()]
    param()

    # The janitor reads this tag to decide whether the controller is alive. Stamped as
    # the last act of a live pass so a half-finished pass never looks healthy.
    $stamp = [DateTimeOffset]::UtcNow.ToString("o")
    if (Test-FleetDryRun -Decision "heartbeat vmss=$($script:Fleet.Vmss) at=$stamp") {
        return
    }
    $vmssId = "/subscriptions/$($script:Fleet.SubscriptionId)/resourceGroups/$($script:Fleet.ResourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($script:Fleet.Vmss)"
    $splatHeartbeat = @{
        VmId      = $vmssId
        VmName    = $script:Fleet.Vmss
        Tags      = @{ fleetHeartbeat = $stamp }
        Operation = "stamp fleet heartbeat"
    }
    Set-VmTag @splatHeartbeat
    Write-Host "heartbeat=$stamp"
}

function Invoke-FleetReconcile {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$DirectTriggerActor = "",
        [AllowEmptyString()]
        [string]$DirectTriggerMessage = "",
        [AllowEmptyString()]
        [string]$DirectTriggerSha = "",
        [AllowEmptyString()]
        [string]$DirectTriggerRef = ""
    )

    $null = Initialize-FleetContext
    if ($script:Fleet.DryRun) {
        Write-Host "DRY_RUN is on: decisions are logged, nothing is mutated"
    }

    if ($DirectTriggerActor -or $DirectTriggerSha) {
        # Logged as the hint it is. The message is deliberately not passed on; the
        # reconcile re-reads it from GitHub so a stale or replayed delivery cannot
        # carry its own marker text into the dispatch decision.
        Write-Host "trigger hint: actor=$DirectTriggerActor ref=$DirectTriggerRef sha=$DirectTriggerSha message=$($DirectTriggerMessage -replace "`r?`n", " ")"
    }

    try {
        $splatDemand = @{
            DirectTriggerActor = $DirectTriggerActor
            DirectTriggerSha   = $DirectTriggerSha
            DirectTriggerRef   = $DirectTriggerRef
        }
        $demand = Get-RunnerDemand @splatDemand
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
                Set-VmPool -Vm $vm -Pool $runnerPool
            } elseif ($runner -and -not $runnerPool -and -not $runner.busy) {
                Remove-FleetVm -State $state -Vm $vm -Reason "legacy runner lacks a pool label"
            }
        }

        $state = Get-FleetState
        Set-UnallocatedVmPool -State $state -Desired $desired
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
        $target = [math]::Min($script:Fleet.MaxRunners, $desiredTotal + $transitionBusy)
        $vmssPath = "/subscriptions/$($script:Fleet.SubscriptionId)/resourceGroups/$($script:Fleet.ResourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($script:Fleet.Vmss)"
        $splatCapacity = @{
            Path      = "$vmssPath`?api-version=2024-07-01"
            Operation = "read VMSS capacity"
        }
        $capacityResponse = Invoke-ArmJson @splatCapacity
        $capacity = [int]$capacityResponse.sku.capacity
        Write-Host "capacity=$capacity target=$target transition_busy=$transitionBusy"
        if ($capacity -lt $target) {
            if (-not (Test-FleetDryRun -Decision "scale vmss=$($script:Fleet.Vmss) from=$capacity to=$target")) {
                # Fire and forget, matching the CLI's --no-wait. Deliberately no in-line
                # readiness poll: the queue is serialized, so a pass that sleeps on
                # provisioning holds up every queued nudge behind it, and a burst of runs
                # put the fleet 3.3 hours behind demand that way (2026-08-08). New
                # instances register on a later pass once they report Succeeded, which a
                # queued nudge or the five-minute safety tick reaches soon enough.
                $splatScale = @{
                    Path      = "$vmssPath`?api-version=2024-07-01"
                    Method    = "Patch"
                    Body      = @{ sku = @{ capacity = $target } }
                    Operation = "scale VMSS to $target"
                }
                $null = Invoke-ArmWeb @splatScale
            }
        }

        $state = Get-FleetState
        Set-UnallocatedVmPool -State $state -Desired $desired
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
        Set-FleetHeartbeat
    } catch [TransientFleetException] {
        Write-Warning "$($PSItem.Exception.Message) No further fleet changes will be attempted; a job-completion nudge or scheduled reconcile will retry."
    }
}

function Invoke-FleetSpendReport {
    [CmdletBinding()]
    param()

    $null = Initialize-FleetContext
    $from = [DateTime]::UtcNow.ToString("yyyy-MM-01")
    $to = [DateTime]::UtcNow.ToString("yyyy-MM-dd")
    $cost = "unavailable"
    try {
        $body = @{
            type       = "ActualCost"
            timeframe  = "Custom"
            timePeriod = @{ from = $from; to = $to }
            dataset    = @{
                granularity = "None"
                aggregation = @{ totalCost = @{ name = "Cost"; function = "Sum" } }
            }
        }
        $splatCost = @{
            Path      = "/subscriptions/$($script:Fleet.SubscriptionId)/resourceGroups/$($script:Fleet.ResourceGroup)/providers/Microsoft.CostManagement/query?api-version=2023-11-01"
            Method    = "Post"
            Body      = $body
            Operation = "query month-to-date spend"
        }
        $costResponse = Invoke-ArmJson @splatCost
        $amount = @($costResponse.properties.rows)[0][0]
        $cost = "{0:N2}" -f [double]$amount
    } catch {
        Write-Warning "Cost Management query failed; reporting unavailable. $($PSItem.Exception.Message)"
    }

    $titleFilter = "`"CI cost tracker`""
    $issueQuery = [uri]::EscapeDataString("repo:$($script:Fleet.Repo) is:issue is:open in:title $titleFilter")
    $splatIssues = @{
        Path      = "search/issues?q=$issueQuery"
        Operation = "find the CI cost tracker issue"
    }
    $search = Invoke-GhJson @splatIssues
    $issueNumber = @($search.items | Select-Object -First 1).number
    if (-not $issueNumber) {
        $splatCreate = @{
            Path      = "repos/$($script:Fleet.Repo)/issues"
            Method    = "Post"
            Body      = @{
                title = "CI cost tracker"
                body  = "Automated month-to-date Azure spend for the self-hosted runner fleet."
            }
            Operation = "open the CI cost tracker issue"
        }
        $issueNumber = (Invoke-GhJson @splatCreate).number
    }
    $comment = "Month-to-date spend for ``$($script:Fleet.ResourceGroup)`` as of $($to): **`$$cost**"
    if (Test-FleetDryRun -Decision "comment issue=$issueNumber body=$comment") {
        return
    }
    $splatComment = @{
        Path      = "repos/$($script:Fleet.Repo)/issues/$issueNumber/comments"
        Method    = "Post"
        Body      = @{ body = $comment }
        Operation = "comment month-to-date spend"
    }
    $null = Invoke-GhJson @splatComment
    Write-Host "posted month-to-date spend $cost to issue $issueNumber"
}

function Get-FleetNudge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$EventName,
        [Parameter(Mandatory)]
        $Payload,
        [Parameter(Mandatory)]
        [string[]]$BoostUsers,
        [Parameter(Mandatory)]
        [string]$RunnerLabel,
        [Parameter(Mandatory)]
        [string]$CiWorkflow
    )

    # Webhook bodies are hints, never decision inputs. All this decides is whether a
    # pass is worth waking; the pass itself re-reads the whole GitHub queue and the
    # whole Azure inventory, so a forged nudge buys an attacker one read-and-converge.
    switch ($EventName) {
        "workflow_job" {
            if ([string]$Payload.action -notin @("queued", "completed")) {
                return $null
            }
            # ci-azure's authorize job runs on ubuntu-latest and emits these events
            # too. Only fleet-labelled jobs mean anything to the controller.
            if (@($Payload.workflow_job.labels) -notcontains $RunnerLabel) {
                return $null
            }
            return @{
                reason = "workflow_job.$([string]$Payload.action)"
            }
        }
        "workflow_run" {
            if ([string]$Payload.action -notin @("requested", "completed")) {
                return $null
            }
            $workflowPath = [string]$Payload.workflow_run.path
            if ($workflowPath -and -not $workflowPath.EndsWith($CiWorkflow)) {
                return $null
            }
            return @{
                reason = "workflow_run.$([string]$Payload.action)"
            }
        }
        "push" {
            $actor = [string]$Payload.sender.login
            if ($actor -notin $BoostUsers) {
                return $null
            }
            # A branch deletion is a push whose after is the all-zeros sha: nothing to
            # corroborate, nothing to dispatch, and the commits endpoint answers 422 to
            # every retry. Squash-merge cleanup fires one of these right behind the
            # merge push, which wakes a pass on its own.
            if ($Payload.deleted -eq $true) {
                return $null
            }
            # The [do ci] gate for opt-in users lives in the policy, not here: it also
            # has to hold for pushes that arrive as repository events rather than as a
            # webhook, and one implementation cannot drift from itself.
            return @{
                reason  = "push"
                actor   = $actor
                message = [string]$Payload.head_commit.message
                sha     = [string]$Payload.after
                ref     = [string]$Payload.ref
            }
        }
    }
    return $null
}

$splatExport = @{
    Function = @(
        "Invoke-FleetReconcile",
        "Invoke-FleetSpendReport",
        "Get-FleetNudge",
        "Initialize-FleetContext",
        "Get-FleetConfig",
        "Get-FleetSetting",
        "Invoke-VmRunCommand"
    )
}
Export-ModuleMember @splatExport
