#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

// The two hops live in their own partial so neither half runs past the 400-line file rule, and each
// C# call site is kept HERE with the body it marshals into rather than with the parameter surface:
// the arg-order detector name-checks a marshal against the body's param() only when it can see both
// in one file, and splitting them apart would silently drop that half of the check. The bodies are
// the source function's process and end blocks verbatim apart from the sanctioned mechanical edits,
// so they are kept whole and unreflowed - a diff against the .ps1 is how this port is audited.
public sealed partial class SyncDbaAvailabilityGroupCommand
{
    // NO Interrupted PROLOGUE - see the type comment. The source's process block never reads the flag.
    protected override void ProcessRecord()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            Primary, PrimarySqlCredential, Secondary, SecondarySqlCredential, AvailabilityGroup,
            InputObject, EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("Primary"),
            MyInvocation.BoundParameters.ContainsKey("InputObject"),
            _processState,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void EndProcessing()
    {
        // Streaming, not buffered: a sync walks fifteen object types across every secondary and emits
        // a result object per copied object, so a buffered hop would withhold the whole run until the
        // last agent job finished.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, EndScript,
            AvailabilityGroup, Exclude, Login, ExcludeLogin, Job, ExcludeJob,
            DisableJobOnDestination.ToBool(), Credential, ExcludePassword.ToBool(), Force.ToBool(),
            EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("Job"),
            MyInvocation.BoundParameters.ContainsKey("ExcludeJob"),
            _processState, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM inside a dot-sourced block, so its three early returns leave the
    // block and the write-back below still runs - which is what makes the carry match the function's
    // single scope. Edits: the two Test-Bound reads become the carried flags, and every Stop-Function
    // carries -FunctionName Sync-DbaAvailabilityGroup so the message names the command, not the hop.
    private const string ProcessScript = """
param($Primary, $PrimarySqlCredential, $Secondary, $SecondarySqlCredential, $AvailabilityGroup, $InputObject, $EnableException, $__boundPrimary, $__boundInputObject, $__processState, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Primary, [PSCredential]$PrimarySqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Secondary, [PSCredential]$SecondarySqlCredential, [string]$AvailabilityGroup, [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject, $EnableException, $__boundPrimary, $__boundInputObject, $__processState, $__boundVerbose, $__boundDebug)

    $allcombos = $__processState.AllCombos
    if ($__processState.Seeded) {
        $Secondary = $__processState.Secondary
        $secondaries = $__processState.Secondaries
    }

    # -WhatIf:$false for the same reason Stop-Function carries it on this variable: the latch is
    # internal plumbing, so a -WhatIf run must neither announce it nor skip writing it.
    Set-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Value ([bool]$__processState.Interrupted) -Scope 0 -WhatIf:$false -Confirm:$false

    . {
        if (-not $__boundPrimary -and -not $__boundInputObject) {
            Stop-Function -Message "You must supply either -Primary or an Input Object" -FunctionName Sync-DbaAvailabilityGroup
            return
        }

        if (-not $AvailabilityGroup -and -not $Secondary -and -not $InputObject) {
            Stop-Function -Message "You must specify a secondary or an availability group." -FunctionName Sync-DbaAvailabilityGroup
            return
        }

        if ($InputObject) {
            $server = $InputObject.Parent
        } else {
            try {
                $server = Connect-DbaInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary -FunctionName Sync-DbaAvailabilityGroup
                return
            }
        }

        if ($AvailabilityGroup) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $AvailabilityGroup
        }

        if ($InputObject) {
            $Secondary += (($InputObject.AvailabilityReplicas | Where-Object Name -ne $server.DomainInstanceName).Name | Select-Object -Unique)
        }

        if ($Secondary) {
            $Secondary = $Secondary | Sort-Object
            $secondaries = @()
            foreach ($computer in $Secondary) {
                try {
                    $secondaries += Connect-DbaInstance -SqlInstance $computer -SqlCredential $SecondarySqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $computer -Continue -FunctionName Sync-DbaAvailabilityGroup
                }
            }
        }

        $thiscombo = [PSCustomObject]@{
            PrimaryServer   = $server
            SecondaryServer = $secondaries
        }

        # In the event that someone pipes in an availability group, this will keep the sync from running a bunch of times
        $dupe = $false

        foreach ($ag in $allcombos) {
            if ($ag.PrimaryServer.Name -eq $thiscombo.PrimaryServer.Name -and
                $ag.SecondaryServer.Name.ToString() -eq $thiscombo.SecondaryServer.Name.ToString()) {
                $dupe = $true
            }
        }

        if ($dupe -eq $false) {
            $allcombos += $thiscombo
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    $__processState.Interrupted = [bool]($__iv -and $__iv.Value)
    $__processState.AllCombos = $allcombos
    $__processState.Secondary = $Secondary
    $__processState.Secondaries = $secondaries
    $__processState.Seeded = $true
} $Primary $PrimarySqlCredential $Secondary $SecondarySqlCredential $AvailabilityGroup $InputObject $EnableException $__boundPrimary $__boundInputObject $__processState $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM inside the named-wrapper shim, with process's $allcombos and latch
    // restored ahead of it. Edits: the two Test-Bound reads become the carried flags, $PSCmdlet
    // becomes $__realCmdlet so the gate reaches the compiled cmdlet's own ShouldProcess, and
    // Stop-Function carries -FunctionName Sync-DbaAvailabilityGroup.
    private const string EndScript = """
param($AvailabilityGroup, $Exclude, $Login, $ExcludeLogin, $Job, $ExcludeJob, $DisableJobOnDestination, $Credential, $ExcludePassword, $Force, $EnableException, $__boundJob, $__boundExcludeJob, $__processState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([string]$AvailabilityGroup, [string[]]$Exclude, [string[]]$Login, [string[]]$ExcludeLogin, [string[]]$Job, [string[]]$ExcludeJob, $DisableJobOnDestination, [PSCredential]$Credential, $ExcludePassword, $Force, $EnableException, $__boundJob, $__boundExcludeJob, $__processState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)

    $allcombos = $__processState.AllCombos

    # The source's begin block set this once for the whole invocation; each hop scope is separate,
    # so it has to be re-set in the one the ShouldProcess call below actually reads.
    if ($Force) { $ConfirmPreference = 'none' }

    # -WhatIf:$false for the same reason Stop-Function carries it on this variable: the latch is
    # internal plumbing, so a -WhatIf run must neither announce it nor skip writing it.
    Set-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Value ([bool]$__processState.Interrupted) -Scope 0 -WhatIf:$false -Confirm:$false

    function Sync-DbaAvailabilityGroup {
        if (Test-FunctionInterrupt) { return }

        # now that all combinations have been figured out, begin sync without duplicating work
        foreach ($ag in $allcombos) {
            $server = $ag.PrimaryServer
            $secondaries = $ag.SecondaryServer

            $stepCounter = 0
            $activity = "Syncing availability group $AvailabilityGroup"

            if (-not $secondaries) {
                Stop-Function -Message "No secondaries found." -FunctionName Sync-DbaAvailabilityGroup
                return
            }

            $primaryserver = $server.Name
            $secondaryservers = $secondaries.Name -join ", "

            if ($Exclude -notcontains "SpConfigure") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL Server Configuration"
                Copy-DbaSpConfigure -Source $server -Destination $secondaries
            }

            if ($Exclude -notcontains "Logins") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing logins"
                Copy-DbaLogin -Source $server -Destination $secondaries -Login $Login -ExcludeLogin $ExcludeLogin -Force:$Force
            }

            if ($Exclude -notcontains "DatabaseOwner") {
                if ($__realCmdlet.ShouldProcess("Updating database owners to match newly migrated logins from $primaryserver to $secondaryservers")) {
                    Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Updating database owners to match newly migrated logins"
                    foreach ($sec in $secondaries) {
                        $null = Update-SqlDbOwner -Source $server -Destination $sec
                    }
                }
            }

            if ($Exclude -notcontains "CustomErrors") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing custom errors (user defined messages)"
                Copy-DbaCustomError -Source $server -Destination $secondaries -Force:$Force
            }

            if ($Exclude -notcontains "Credentials") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing SQL credentials"
                Copy-DbaCredential -Source $server -Destination $secondaries -Credential $Credential -ExcludePassword:$ExcludePassword -Force:$Force
            }

            if ($Exclude -notcontains "DatabaseMail") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing database mail"
                Copy-DbaDbMail -Source $server -Destination $secondaries -Credential $Credential -ExcludePassword:$ExcludePassword -Force:$Force
            }

            if ($Exclude -notcontains "LinkedServers") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing linked servers"
                Copy-DbaLinkedServer -Source $server -Destination $secondaries -Credential $Credential -ExcludePassword:$ExcludePassword -Force:$Force
            }

            if ($Exclude -notcontains "SystemTriggers") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing System Triggers"
                Copy-DbaInstanceTrigger -Source $server -Destination $secondaries -Force:$Force
            }

            if ($Exclude -notcontains "AgentCategory") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Categories"
                Copy-DbaAgentJobCategory -Source $server -Destination $secondaries -Force:$force
                foreach ($sec in $secondaries) {
                    if ($sec.JobServer) {
                        $sec.JobServer.JobCategories.Refresh()
                        $sec.JobServer.OperatorCategories.Refresh()
                        $sec.JobServer.AlertCategories.Refresh()
                    }
                }
            }

            if ($Exclude -notcontains "AgentOperator") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Operators"
                Copy-DbaAgentOperator -Source $server -Destination $secondaries -Force:$force
                foreach ($sec in $secondaries) {
                    if ($sec.JobServer) {
                        $sec.JobServer.Operators.Refresh()
                    }
                }
            }

            if ($Exclude -notcontains "AgentAlert") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Alerts"
                Copy-DbaAgentAlert -Source $server -Destination $secondaries -Force:$force -IncludeDefaults
            }

            if ($Exclude -notcontains "AgentProxy") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Proxy Accounts"
                Copy-DbaAgentProxy -Source $server -Destination $secondaries -Force:$force
                foreach ($sec in $secondaries) {
                    if ($sec.JobServer) {
                        $sec.JobServer.ProxyAccounts.Refresh()
                    }
                }
            }

            if ($Exclude -notcontains "AgentSchedule") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Schedules"
                Copy-DbaAgentSchedule -Source $server -Destination $secondaries -Force:$force
                foreach ($sec in $secondaries) {
                    if ($sec.JobServer) {
                        $sec.JobServer.SharedSchedules.Refresh()
                        $sec.JobServer.Refresh()
                    }
                    $sec.Refresh()
                }
            }

            if ($Exclude -notcontains "AgentJob") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing Agent Jobs"
                $splatGetJob = @{
                    SqlInstance = $server
                    Type        = "Local"
                }
                if ($__boundJob) {
                    $splatGetJob['Job'] = $Job
                }
                if ($__boundExcludeJob) {
                    $splatGetJob['ExcludeJob'] = $ExcludeJob
                }
                $jobsToSync = Get-DbaAgentJob @splatGetJob

                $splatCopyJob = @{
                    Destination          = $secondaries
                    Force                = $force
                    DisableOnDestination = $DisableJobOnDestination
                    InputObject          = $jobsToSync
                }
                Copy-DbaAgentJob @splatCopyJob
            }

            if ($Exclude -notcontains "LoginPermissions") {
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Syncing login permissions"
                Sync-DbaLoginPermission -Source $server -Destination $secondaries -Login $Login -ExcludeLogin $ExcludeLogin
            }
        }
    }
    . Sync-DbaAvailabilityGroup
} $AvailabilityGroup $Exclude $Login $ExcludeLogin $Job $ExcludeJob $DisableJobOnDestination $Credential $ExcludePassword $Force $EnableException $__boundJob $__boundExcludeJob $__processState $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
