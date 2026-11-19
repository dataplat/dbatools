#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Restores databases from their snapshots. Port of public/Restore-DbaDbSnapshot.ps1; the workflow
/// remains a module-scoped PowerShell compatibility hop.
///
/// The source's begin block does one thing - "if ($Force) { $ConfirmPreference = 'none' }" - and it
/// is folded into the top of the hop body rather than run as a separate begin hop: -Force is not a
/// pipeline parameter, so setting the preference per record is identical to setting it once.
///
/// That fold is only correct because a $ConfirmPreference set INSIDE the hop still reaches a gate
/// routed to the outer cmdlet, which is not obvious - ShouldProcess resolves the preference from the
/// scope chain at call time rather than from the cmdlet's own scope. Measured before relying on it:
/// with ConfirmImpact High and no explicit -Confirm, the hop-sets-preference / outer-owned-gate shape
/// executes without prompting, matching the script-function shape, while the same gate with no
/// preference set does attempt a prompt. So -Force still suppresses confirmation here.
///
/// Both ShouldProcess gates are routed to the OUTER cmdlet ($Pscmdlet becomes $__realCmdlet), which
/// also keeps -Confirm's "Yes to All" answer alive across pipeline records instead of letting a
/// per-record inner runtime forget it.
///
/// The hop stays WHOLE-ARRAY rather than splitting per instance: the instance loop exists to
/// accumulate into $InputObject ($InputObject += Get-DbaDbSnapshot ...), which is cross-instance
/// state and the per-element rule's stated exemption. A second loop then walks $InputObject, so the
/// two loops are not independent and cannot be split.
///
/// No local needs a cross-record carry. $InputObject is re-bound from the pipeline on every record
/// before the accumulation runs. $server is assigned in the instance loop and REASSIGNED from
/// $snap.Parent at the top of each snapshot iteration, inside the "if ($snap.Parent)" guard that
/// dominates every later use. $dbs and $baseDatabases are confined to the "if ($Snapshot)" block;
/// $db, $loginfo, $othersnaps, $log, $matching and $changeflag are each assigned and read within one
/// snapshot iteration. The retry locals ($maxRetries, $retryCount, $restoreSuccess) are assigned and
/// read entirely inside the second gate's block, so a declined gate reads none of them.
///
/// No graceful-stop latch: the source has no Test-FunctionInterrupt guard, so a later record
/// re-enters the process body and re-evaluates its input guard, warning again - carrying a latch
/// would suppress warnings the function repeats.
///
/// The bare "continue" after a failed retry loop and the "break" inside that loop's catch both bind
/// to constructs within a single hop invocation, so neither escapes to abort the piped invocation.
///
/// The hop streams rather than buffers. This command RESTORES databases - each emitted object is the
/// record of a database that was actually restored - so a buffered invocation would discard the
/// records of completed restores if a later snapshot threw under -EnableException.
/// </summary>
[Cmdlet(VerbsData.Restore, "DbaDbSnapshot", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class RestoreDbaDbSnapshotCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases to restore to.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Databases to skip.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>The snapshot or snapshots to restore from.</summary>
    [Parameter(Position = 4)]
    public object[]? Snapshot { get; set; }

    /// <summary>Snapshot objects, typically from Get-DbaDbSnapshot.</summary>
    [Parameter(Position = 5, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Drop other snapshots that block the restore, and kill blocking processes.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BodyScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Snapshot, InputObject, Force,
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's begin line followed by its process body VERBATIM. Substitutions only:
    // $Pscmdlet -> $__realCmdlet, and -FunctionName on Stop-Function/Write-Message.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Snapshot, $InputObject, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [object[]]$Snapshot, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

            if ($Force) { $ConfirmPreference = 'none' }

            if (-not $Snapshot -and -not $Database -and -not $ExcludeDatabase -and -not $InputObject) {
                Stop-Function -Message "You must specify either -Snapshot (to restore from) or -Database/-ExcludeDatabase (to restore to) or pipe in a snapshot" -FunctionName Restore-DbaDbSnapshot
                return
            }

            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Restore-DbaDbSnapshot
                }

                $InputObject += Get-DbaDbSnapshot -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -Snapshot $Snapshot | Sort-Object CreateDate -Descending

                if ($Snapshot) {
                    # Restore databases from these snapshots
                    Write-Message -Level Verbose -Message "Selected only snapshots" -FunctionName Restore-DbaDbSnapshot -ModuleName "dbatools"
                    $dbs = $InputObject | Where-Object { $Snapshot -contains $_.Name }
                    $baseDatabases = $dbs | Select-Object -ExpandProperty DatabaseSnapshotBaseName | Get-Unique
                    if ($baseDatabases.Count -ne $Snapshot.Count -and $dbs.Count -ne 0) {
                        Stop-Function -Message "Failure. Multiple snapshots selected for the same database" -Continue -FunctionName Restore-DbaDbSnapshot
                    }
                }
            }

            foreach ($snap in $InputObject) {
                # In the event someone passed -Database and it got all the snaps, most of which were dropped by the first
                if ($snap.Parent) {
                    $server = $snap.Parent

                    if (-not $snap.IsDatabaseSnapshot) {
                        Stop-Function -Continue -Message "$snap on $server is not a valid snapshot" -FunctionName Restore-DbaDbSnapshot
                    }

                    if (-not ($snap.IsAccessible)) {
                        Stop-Function -Message "Database $snap is not accessible on $($snap.Parent)." -Continue -FunctionName Restore-DbaDbSnapshot
                    }

                    $othersnaps = $server.Databases | Where-Object { $_.DatabaseSnapshotBaseName -eq $snap.DatabaseSnapshotBaseName -and $_.Name -ne $snap.Name }

                    $db = $server.Databases | Where-Object Name -eq $snap.DatabaseSnapshotBaseName
                    $loginfo = $db.LogFiles | Select-Object Id, Size, Growth, GrowthType

                    if (($snap | Where-Object FileGroupType -eq 'FileStreamDataFileGroup')) {
                        Stop-Function -Message "Database $snap on $server has FileStream group(s). You cannot restore from snapshots" -Continue -FunctionName Restore-DbaDbSnapshot
                    }

                    if ($othersnaps -and -not $force) {
                        Stop-Function -Message "The restore process for $db from $snap needs to drop other snapshots on $db. Use -Force if you want to drop these snapshots" -Continue -FunctionName Restore-DbaDbSnapshot
                    }

                    if ($__realCmdlet.ShouldProcess($server, "Remove other db snapshots for $db")) {
                        try {
                            $null = $othersnaps | Remove-DbaDatabase -Confirm:$false -EnableException
                        } catch {
                            Stop-Function -Message "Failed to remove other snapshots for $db on $server" -ErrorRecord $_ -Continue -FunctionName Restore-DbaDbSnapshot
                        }
                    }

                    # Need a proper restore now
                    if ($__realCmdlet.ShouldProcess($server, "Restore db $db from $snap")) {
                        $maxRetries = 3
                        $retryCount = 0
                        $restoreSuccess = $false

                        while (-not $restoreSuccess -and $retryCount -lt $maxRetries) {
                            try {
                                if ($Force) {
                                    $null = Stop-DbaProcess -SqlInstance $server -Database $db.Name, $snap.Name -WarningAction SilentlyContinue
                                }

                                $null = $server.Query("USE master; RESTORE DATABASE [$($db.Name)] FROM DATABASE_SNAPSHOT = '$($snap.Name)'")
                                $restoreSuccess = $true
                            } catch {
                                # Check if this is a deadlock error (error 1205)
                                if ($_.Exception.InnerException.Number -eq 1205) {
                                    $retryCount++
                                    if ($retryCount -lt $maxRetries) {
                                        $waitSeconds = [Math]::Pow(2, $retryCount)
                                        Write-Message -Level Verbose -Message "Deadlock detected during restore of $db on $server. Retrying in $waitSeconds seconds (attempt $retryCount of $maxRetries)" -FunctionName Restore-DbaDbSnapshot -ModuleName "dbatools"
                                        Start-Sleep -Seconds $waitSeconds
                                    } else {
                                        Stop-Function -Message "Failiure attempting to restore $db on $server after $maxRetries attempts due to deadlock" -ErrorRecord $_ -Continue -FunctionName Restore-DbaDbSnapshot
                                    }
                                } else {
                                    Stop-Function -Message "Failiure attempting to restore $db on $server" -ErrorRecord $_ -Continue -FunctionName Restore-DbaDbSnapshot
                                    break
                                }
                            }
                        }

                        if (-not $restoreSuccess) {
                            continue
                        }
                    }

                    # Comparing sizes before and after, need to refresh to see if size
                    foreach ($log in $db.LogFiles) {
                        $log.Refresh()
                    }

                    foreach ($log in $db.LogFiles) {
                        $matching = $loginfo | Where-Object ID -eq $log.ID
                        $changeflag = 0
                        foreach ($prop in @('Size', 'Growth', 'Growth', 'GrowthType')) {
                            if ($matching.$prop -ne $log.$prop) {
                                $changeflag = 1
                                $log.$prop = $matching.$prop
                            }
                        }
                        if ($changeflag -ne 0) {
                            Write-Message -Level Verbose -Message "Restoring original settings for log file" -FunctionName Restore-DbaDbSnapshot -ModuleName "dbatools"
                            $log.Alter()
                        }
                    }

                    Write-Message -Level Verbose -Message "Restored. Remember to take a backup now, and also to remove the snapshot if not needed." -FunctionName Restore-DbaDbSnapshot -ModuleName "dbatools"
                    Get-DbaDatabase -SqlInstance $server -Database $db.Name
                }
            }

} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Snapshot $InputObject $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
