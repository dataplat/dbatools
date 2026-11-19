#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Synchronizes SQL Server login permissions from a source instance to one or more destination instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the permission sync, the
/// ShouldProcess gate, the output shape, and dbatools stream and error handling stay observable-identical to the
/// script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, and it streams its output through InvokeScopedStreaming: it emits
/// one object per login synced per destination. Source is the only ValueFromPipeline parameter (a singular
/// DbaInstanceParameter; Destination is a Mandatory non-pipeline array), and the body only READS $Source (no
/// mutation), so there is no cross-record accumulation and a per-record hop is faithful. The callback dispatches
/// ErrorRecords to WriteError, else WriteObject. EnableException is carried as a plain (untyped) value, because a
/// switch in the inner CmdletBinding scriptblock is excluded from positional binding. The eight edits are the
/// ShouldProcess redirect to $__realCmdlet and -FunctionName on the seven DIRECT Stop-Function/Write-Message
/// calls; Connect-DbaInstance, Get-DbaLogin, Update-SqlPermission, Get-ErrorMessage, and Write-ProgressHelper are
/// left unedited.
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Sync, "DbaLoginPermission", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SyncDbaLoginPermissionCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance to copy permissions from.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter? Source { get; set; }

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instance or instances to sync permissions to.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[]? Destination { get; set; }

    /// <summary>Alternative credential for the destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>The specific logins to sync.</summary>
    [Parameter(Position = 4)]
    public string[]? Login { get; set; }

    /// <summary>The logins to exclude from the sync.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeLogin { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>
    /// Set once the hop body latches the dbatools interrupt (DEF-011).
    /// </summary>
    /// <remarks>
    /// The body opens with `if (Test-FunctionInterrupt) { return }`, so in the function world one hard
    /// Stop-Function latches the interrupt in the persistent function scope and EVERY later record returns
    /// immediately. An in-hop Stop-Function cannot set DbaBaseCmdlet.Interrupted, and each record gets a
    /// fresh hop scope, so without carrying the latch out the gate never fires and later records re-run the
    /// work - warning once per record instead of once per invocation.
    /// </remarks>
    private bool _interruptLatched;

    /// <summary>Syncs login permissions for one pipeline record.</summary>
    protected override void ProcessRecord()
    {
        if (_interruptLatched || Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__SyncDbaLoginPermissionProcessComplete"]?.Value))
            {
                _interruptLatched = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            Source, SourceSqlCredential, Destination, DestinationSqlCredential, Login, ExcludeLogin, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitutions only: $PSCmdlet -> $__realCmdlet (the ShouldProcess gate);
    // -FunctionName on the seven DIRECT Stop-Function/Write-Message calls. EnableException received untyped.
    private const string ProcessScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $Login, $ExcludeLogin, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, [System.Management.Automation.PSCredential]$SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, [System.Management.Automation.PSCredential]$DestinationSqlCredential, [string[]]$Login, [string[]]$ExcludeLogin, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # try/finally, NOT a trailing line: the body RETURNS early at the interrupt gate and again after the
    # connection-failure Stop-Function - which is the very call that latches the interrupt. A trailing
    # sentinel would be skipped exactly when the latch matters most. finally always runs.
    try {
        if (Test-FunctionInterrupt) { return }

        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Sync-DbaLoginPermission
            return
        }

        $allLogins = Get-DbaLogin -SqlInstance $sourceServer -Login $Login -ExcludeLogin $ExcludeLogin
        if ($null -eq $allLogins) {
            Stop-Function -Message "No matching logins found for $($Login -join ', ') on $Source" -FunctionName Sync-DbaLoginPermission
            return
        }

        # Get current login to not sync permissions for that login.
        $currentLogin = $sourceServer.ConnectionContext.TrueLogin

        foreach ($dest in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $dest -SqlCredential $DestinationSqlCredential -MinimumVersion 8
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $dest -Continue -FunctionName Sync-DbaLoginPermission
            }

            $stepCounter = 0
            foreach ($sourceLogin in $allLogins) {
                $loginName = $sourceLogin.Name
                if ($currentLogin -eq $loginName) {
                    Write-Message -Level Verbose -Message "Sync does not modify the permissions of the current login '$loginName'. Skipping." -FunctionName Sync-DbaLoginPermission -ModuleName "dbatools"
                    continue
                }

                # Here we don't need the FullComputerName, but only the machine name to compare to the host part of the login name. So ComputerName should be fine.
                $serverName = $sourceServer.ComputerName
                $userBase = ($loginName.Split("\")[0]).ToLowerInvariant()
                if ($serverName -eq $userBase -or $loginName.StartsWith("NT ")) {
                    Write-Message -Level Verbose -Message "Sync does not modify the permissions of host or system login '$loginName'. Skipping." -FunctionName Sync-DbaLoginPermission -ModuleName "dbatools"
                    continue
                }

                if ($null -eq ($destLogin = $destServer.Logins.Item($loginName))) {
                    Write-Message -Level Verbose -Message "Login '$loginName' not found on destination. Skipping." -FunctionName Sync-DbaLoginPermission -ModuleName "dbatools"
                    continue
                }


                $copyLoginPermissionStatus = [PSCustomObject]@{
                    SourceServer      = $sourceserver.Name
                    DestinationServer = $destServer.Name
                    Name              = $loginName
                    Type              = "Login Permissions"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }
                Write-ProgressHelper -Activity "Executing Sync-DbaLoginPermission to sync login permissions from $($sourceServer.Name)" -StepNumber ($stepCounter++) -Message "Updating permissions for $loginName on $($destServer.Name)" -TotalSteps $allLogins.Count
                try {
                    Update-SqlPermission -SourceServer $sourceServer -SourceLogin $sourceLogin -DestServer $destServer -DestLogin $destLogin -EnableException
                    $copyLoginPermissionStatus.Status = "Successful"
                    if ($__realCmdlet.ShouldProcess("Console", "Outputting results for login $loginName permission sync")) {
                        $copyLoginPermissionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                } catch {
                    $copyLoginPermissionStatus.Status = "Failed"
                    $copyLoginPermissionStatus.Notes = (Get-ErrorMessage -Record $_)
                    $copyLoginPermissionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Stop-Function -Message "Issue syncing permissions for login" -Target $loginName -ErrorRecord $_ -Continue -FunctionName Sync-DbaLoginPermission
                }
            }
        }

    } finally {
    [pscustomobject]@{ __SyncDbaLoginPermissionProcessComplete = $true; Interrupted = [bool](Test-FunctionInterrupt) }
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $Login $ExcludeLogin $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
