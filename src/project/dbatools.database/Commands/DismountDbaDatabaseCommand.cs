#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Detaches user databases. Port of public/Dismount-DbaDatabase.ps1; the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// The process body rides one VERBATIM module hop per record. $InputObject does not leak across
/// records because the parameter sets are mutually exclusive: in the "SqlInstance" set process
/// fires once and $InputObject accumulates only within that invocation's SqlInstance loop; in the
/// "Pipeline" set the piped $InputObject rebinds every record (the Remove-DbaDatabase / W3-063
/// shape). $server is reassigned unconditionally at the top of each loop. But ONE local does carry:
/// $exception (see the field above) is assigned only in the AG-removal catch and read there
/// unconditionally, so it rides the process-complete sentinel with an ExceptionAssigned flag,
/// preserving unset-vs-assigned so an unset read walks the scope chain as the function's did.
///
/// The source's begin block does one thing - "if ($Force) { $ConfirmPreference = 'none' }" - and it
/// is folded into the top of the hop body rather than run as a separate begin hop: -Force is not a
/// pipeline parameter, so setting the preference per-record is identical to setting it once, and
/// ShouldProcess reads $ConfirmPreference from the call-site scope (the Copy-DbaAgentAlert pattern).
///
/// Every Stop-Function here is -Continue (skip the current database and keep looping), and the one
/// bare Continue is a plain loop continue, so a failure never halts later records and there is no
/// interrupt carry to thread. The five $Pscmdlet.ShouldProcess gates route to the real cmdlet via
/// $__realCmdlet (ConfirmImpact Medium mirrored); -WhatIf and -Confirm ride the carriers.
///
/// The body references $ExcludeDatabase, which the source never declares as a parameter - it is an
/// unset variable whose "if ($ExcludeDatabase)" branch never fires. It ships verbatim; an unset read
/// walks the scope chain exactly as the function's did. In-hop Stop-Function/Write-Message carry
/// -FunctionName; the nested Get-DbaProcess/Get-DbaDbSnapshot/Stop-DbaProcess resolve through the
/// module scope. Surface pinned by migration/baselines/Dismount-DbaDatabase.json (three parameter
/// sets, no positions).
/// </summary>
[Cmdlet(VerbsData.Dismount, "DbaDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium, DefaultParameterSetName = "Default")]
public sealed class DismountDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "SqlInstance")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to detach.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "SqlInstance")]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>SMO Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Pipeline")]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Update distribution statistics before detaching.</summary>
    [Parameter]
    public SwitchParameter UpdateStatistics { get; set; }

    /// <summary>Kill connections, break mirrors, and drop from availability groups to force the
    /// detach.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The source's $exception is a function-scope local: assigned only inside the AG-removal
    // catch's "if ($_.Exception.InnerException)" and read unconditionally in that catch's
    // Stop-Function message, so it persists across records. A record whose AG error has no inner
    // exception reuses the previous record's parsed suffix; a hop-local would die and read empty.
    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Streaming, not buffered (DEF-001): this is a DESTRUCTIVE command whose per-database
        // result objects are the audit trail of what was detached. Buffered InvokeScoped only
        // returns output after the whole hop completes, so a terminating error mid-loop (under
        // -EnableException) discarded the records for databases ALREADY DETACHED. Streaming
        // emits each result as produced, exactly as the function world did.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__dismountDbaDatabaseState"))
            {
                _state = sentinel["__dismountDbaDatabaseState"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, InputObject, UpdateStatistics.ToBool(),
            Force.ToBool(), EnableException.ToBool(), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only: $Pscmdlet ->
    // $__realCmdlet and -FunctionName Dismount-DbaDatabase on every Stop-Function/Write-Message. The
    // undeclared $ExcludeDatabase reference, the bare Connect-DbaInstance, the mirror/AG/session
    // handling, the interpolated messages, and the DetachDatabase call all ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $InputObject, $UpdateStatistics, $Force, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $UpdateStatistics, $Force, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # the source's begin block, folded here (its only effect is $ConfirmPreference, stable across
    # records because -Force is not a pipeline parameter, so per-record is identical to run-once)
    if ($Force) { $ConfirmPreference = 'none' }

    # cross-record carry of the AG-catch $exception: restore only when an earlier record assigned it
    if ($null -ne $__state -and $__state.ExceptionAssigned) {
        $exception = $__state.Exception
    }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Dismount-DbaDatabase
            }

            if ($Database) {
                $InputObject += $server.Databases | Where-Object Name -in $Database
            } else {
                $InputObject += $server.Databases
            }

            if ($ExcludeDatabase) {
                $InputObject = $InputObject | Where-Object Name -NotIn $ExcludeDatabase
            }
        }

        foreach ($db in $InputObject) {
            $db.Refresh()
            $server = $db.Parent

            if ($db.IsSystemObject) {
                Stop-Function -Message "$db is a system database and cannot be detached using this method." -Target $db -Continue -FunctionName Dismount-DbaDatabase
            }

            Write-Message -Level Verbose -Message "Checking replication status." -FunctionName Dismount-DbaDatabase -ModuleName "dbatools"
            if ($db.ReplicationOptions -ne "None") {
                Stop-Function -Message "Skipping $db  on $server because it is replicated." -Target $db -Continue -FunctionName Dismount-DbaDatabase
            }

            # repeat because different servers could be piped in
            $snapshots = (Get-DbaDbSnapshot -SqlInstance $server).SnapshotOf
            Write-Message -Level Verbose -Message "Checking for snaps" -FunctionName Dismount-DbaDatabase -ModuleName "dbatools"
            if ($db.Name -in $snapshots) {
                Write-Message -Level Warning -Message "Database $db has snapshots, you need to drop them before detaching. Skipping $db on $server." -FunctionName Dismount-DbaDatabase -ModuleName "dbatools"
                Continue
            }

            Write-Message -Level Verbose -Message "Checking mirror status" -FunctionName Dismount-DbaDatabase -ModuleName "dbatools"
            if ($db.IsMirroringEnabled -and !$Force) {
                Stop-Function -Message "$db on $server is being mirrored. Use -Force to break mirror or use the safer backup/restore method." -Target $db -Continue -FunctionName Dismount-DbaDatabase
            }

            Write-Message -Level Verbose -Message "Checking Availability Group status" -FunctionName Dismount-DbaDatabase -ModuleName "dbatools"

            if ($db.AvailabilityGroupName -and !$Force) {
                $ag = $db.AvailabilityGroupName
                Stop-Function -Message "$db on $server is part of an Availability Group ($ag). Use -Force to drop from $ag availability group to detach. Alternatively, you can use the safer backup/restore method." -Target $db -Continue -FunctionName Dismount-DbaDatabase
            }

            $sessions = Get-DbaProcess -SqlInstance $db.Parent -Database $db.Name

            if ($sessions -and !$Force) {
                Stop-Function -Message "$db on $server currently has connected users and cannot be dropped. Use -Force to kill all connections and detach the database." -Target $db -Continue -FunctionName Dismount-DbaDatabase
            }

            if ($force) {

                if ($sessions) {
                    If ($__realCmdlet.ShouldProcess($server, "Killing $($sessions.count) sessions which are connected to $db")) {
                        $null = $sessions | Stop-DbaProcess -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                    }
                }

                if ($db.IsMirroringEnabled) {
                    If ($__realCmdlet.ShouldProcess($server, "Breaking mirror for $db on $server")) {
                        try {
                            Write-Message -Level Warning -Message "Breaking mirror for $db on $server." -FunctionName Dismount-DbaDatabase -ModuleName "dbatools"
                            $db.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                            $db.Alter()
                            $db.Refresh()
                        } catch {
                            Stop-Function -Message "Could not break mirror for $db on $server - not detaching." -Target $db -ErrorRecord $_ -Continue -FunctionName Dismount-DbaDatabase
                        }
                    }
                }

                if ($db.AvailabilityGroupName) {
                    $ag = $db.AvailabilityGroupName
                    If ($__realCmdlet.ShouldProcess($server, "Attempting remove $db on $server from Availability Group $ag")) {
                        try {
                            $server.AvailabilityGroups[$ag].AvailabilityDatabases[$db.name].Drop()
                            Write-Message -Level Verbose -Message "Successfully removed $db from  detach from $ag on $server." -FunctionName Dismount-DbaDatabase -ModuleName "dbatools"
                        } catch {
                            if ($_.Exception.InnerException) {
                                $exception = $_.Exception.InnerException.ToString() -Split "Microsoft.Data.SqlClient.SqlException: "
                                $exception = " | $(($exception[1] -Split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0])".TrimEnd()
                            }

                            Stop-Function -Message "Could not remove $db from $ag on $server $exception." -Target $db -ErrorRecord $_ -Continue -FunctionName Dismount-DbaDatabase
                        }
                    }
                }

                $sessions = Get-DbaProcess -SqlInstance $db.Parent -Database $db.Name

                if ($sessions) {
                    If ($__realCmdlet.ShouldProcess($server, "Killing $($sessions.count) sessions which are still connected to $db")) {
                        $null = $sessions | Stop-DbaProcess -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                    }
                }
            }

            If ($__realCmdlet.ShouldProcess($server, "Detaching $db on $server")) {
                try {
                    $dbID = $db.ID
                    $server.DetachDatabase($db.Name, $UpdateStatistics)

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        DatabaseID   = $dbID
                        DetachResult = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failure" -Target $db -ErrorRecord $_ -Continue -FunctionName Dismount-DbaDatabase
                }
            }
        }

    # carry $exception forward only if it exists at this scope (assigned by the restore above or by
    # the AG catch this record) - Get-Variable -Scope 0 misses an up-scope $exception, so an unset
    # local stays unset next record and reads empty, exactly as the function-scope variable does
    $__ev = Get-Variable -Name exception -Scope 0 -ErrorAction Ignore
    if ($__ev) {
        @{ __dismountDbaDatabaseState = @{ Exception = $__ev.Value; ExceptionAssigned = $true } }
    } else {
        @{ __dismountDbaDatabaseState = @{ ExceptionAssigned = $false } }
    }
} $SqlInstance $SqlCredential $Database $InputObject $UpdateStatistics $Force $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
