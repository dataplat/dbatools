#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a filegroup in one or more databases. Port of public/New-DbaDbFileGroup.ps1; the workflow
/// remains a module-scoped PowerShell compatibility hop.
///
/// PROCESS-ONLY, one hop. $InputObject is ValueFromPipeline, so process fires per piped database.
///
/// NO INTERRUPT CARRY ON THIS ROW, AND THAT IS DELIBERATE. The two guards at source :113-121
/// ("FileGroup is required", "Database is required when SqlInstance is specified") are Stop-Function
/// WITHOUT -Continue, so they DO set the module interrupt latch - but this source contains NO
/// Test-FunctionInterrupt anywhere. Nothing ever reads the latch back, so the guards simply
/// re-evaluate identically on every record and the source warns PER RECORD. Bridging the latch here
/// would emit ONE warning where the source emits N: the inverse of the interrupt-latch defect, and
/// just as much a divergence. The general rule this row establishes: bridge the latch only where the
/// SOURCE reads it back: no Test-FunctionInterrupt means no carry. Measured mechanism and the
/// converse case are recorded in migration/logs/probe-20260718-latch-sentinel.
///
/// NO CROSS-RECORD STATE CARRY EITHER, and the reasoning is the cheap branch rather than an
/// omission. Source :124 does "$InputObject += Get-DbaDatabase ..." inside a foreach over
/// $SqlInstance, which is the accumulate-into-a-parameter shape that DID carry on New-DbaDacProfile
/// (W2-142). It does not carry here because the mutated variable IS THE PIPELINE-BOUND PARAMETER:
/// the binder rewrites $InputObject before every record, so the append cannot outlive its record.
/// On W2-142 the same append targeted $ConnectionString, a NON-pipeline parameter the binder never
/// rewrites, and it did carry. That is the whole discriminator, and it is why this row needs no
/// sentinel. Every process-block local was enumerated, not just the parameters - the omission that
/// produced the Move-DbaDbFile P1 - and the only other local, $newFileGroup, is assigned and
/// consumed inside a single loop iteration.
///
/// FOUR Test-Bound SITES BECOME CARRIED CALLER-BOUNDNESS FLAGS (Test-Bound never rides a hop):
/// FileGroup, SqlInstance and Database at :113/:118, and FileGroupType at :137. FileGroupType is the
/// one worth noting: it carries a "RowsFileGroup" DEFAULT yet is Test-Bound gated, so the SMO
/// FileGroupType property is set only when the caller passed the parameter explicitly. Its flag
/// therefore has to come from MyInvocation.BoundParameters - a C# property initializer cannot
/// express it, because the initializer makes the property indistinguishable from an explicit pass.
///
/// STREAMING, NOT BUFFERED (DEF-001): this command CREATES filegroups and emits $newFileGroup per
/// database, so a buffered InvokeScoped would discard the record of filegroups already created when
/// a later database's failure terminated the hop under -EnableException.
///
/// The one $Pscmdlet.ShouldProcess gate at :133 routes to the real cmdlet via $__realCmdlet. The two
/// in-loop Stop-Function calls (:130 duplicate filegroup, :144 create failure) carry -Continue, so
/// they skip that database and keep looping. In-hop Stop-Function calls carry -FunctionName.
/// Implicit positions 0-5 are made explicit per the W2-071 law; the switch carries none. Surface
/// pinned by migration/baselines/New-DbaDbFileGroup.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbFileGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbFileGroupCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the filegroup is created in.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The name of the filegroup to create.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? FileGroup { get; set; }

    /// <summary>The filegroup type; only applied when explicitly passed.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("FileStreamDataFileGroup", "MemoryOptimizedDataFileGroup", "RowsFileGroup")]
    [PsStringCast]
    public string FileGroupType { get; set; } = "RowsFileGroup";

    /// <summary>Databases piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {

        // Streaming, not buffered (DEF-001): filegroups are created one database at a time and each
        // one is emitted, so a buffered hop would drop the audit trail of work already performed.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, FileGroup, FileGroupType, InputObject,
            EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("FileGroup"),
            MyInvocation.BoundParameters.ContainsKey("SqlInstance"),
            MyInvocation.BoundParameters.ContainsKey("Database"),
            MyInvocation.BoundParameters.ContainsKey("FileGroupType"),
            this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM, dot-sourced so its two early returns exit only the body and
    // not the whole hop. Edits: the four Test-Bound probes become carried caller-boundness flags,
    // the one $Pscmdlet gate routes to $__realCmdlet, and -FunctionName is stamped on the four
    // Stop-Function calls. NO sentinel epilogue: this source never reads the interrupt latch back
    // (no Test-FunctionInterrupt), so the guards must re-warn per record exactly as they do here.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $FileGroup, $FileGroupType, $InputObject, $EnableException, $__boundFileGroup, $__boundSqlInstance, $__boundDatabase, $__boundFileGroupType, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$FileGroup, [string]$FileGroupType, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundFileGroup, $__boundSqlInstance, $__boundDatabase, $__boundFileGroupType, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {

        if (-not $__boundFileGroup) {
            Stop-Function -Message "FileGroup is required" -FunctionName New-DbaDbFileGroup
            return
        }

        if (($__boundSqlInstance) -and (-not $__boundDatabase)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName New-DbaDbFileGroup
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {

            if ($db.FileGroups.Name -contains $FileGroup) {
                Stop-Function -Message "Filegroup $FileGroup already exists in the database $($db.Name) on $($db.Parent.Name)" -FunctionName New-DbaDbFileGroup -Continue
            }

            if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Creating the filegroup $FileGroup on the database $($db.Name) on $($db.Parent.Name)")) {
                try {
                    $newFileGroup = New-Object Microsoft.SqlServer.Management.Smo.FileGroup -ArgumentList $db, $FileGroup

                    if ($__boundFileGroupType) {
                        $newFileGroup.FileGroupType = [Microsoft.SqlServer.Management.Smo.FileGroupType]::$FileGroupType
                    }

                    $newFileGroup.Create()
                    $newFileGroup
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to create the filegroup $FileGroup in the database $($db.Name)" -FunctionName New-DbaDbFileGroup -ErrorRecord $_ -Continue
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $FileGroup $FileGroupType $InputObject $EnableException $__boundFileGroup $__boundSqlInstance $__boundDatabase $__boundFileGroupType $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
