#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates one or more schemas in a database. Port of public/New-DbaDbSchema.ps1; the workflow
/// remains a module-scoped PowerShell compatibility hop.
///
/// PROCESS-ONLY, one hop. $InputObject is ValueFromPipeline, so process fires per piped database.
/// Structurally the same template as New-DbaDbFileGroup (W2-144), and the same three rulings apply -
/// verified against this source rather than carried over on resemblance.
///
/// NO INTERRUPT BRIDGE, deliberately. The two guards at :106-114 ("Schema is required", "Database is
/// required when SqlInstance is specified") are Stop-Function WITHOUT -Continue, so they DO set the
/// module latch, but this source contains NO Test-FunctionInterrupt anywhere to read it back. The
/// guards therefore re-evaluate and warn on EVERY record, and bridging would emit ONE warning where
/// the source emits N. Bridge only where the SOURCE reads the latch back; contrast W2-145, which
/// reads it at :249 and does bridge. Mechanism measured in logs/probe-20260718-latch-sentinel.
///
/// NO CROSS-RECORD CARRY. Source :117 does "$InputObject += Get-DbaDatabase ..." but the mutated
/// variable IS THE PIPELINE-BOUND PARAMETER, which the binder rewrites before every record, so the
/// append cannot outlive its record - the cheap branch. Contrast New-DbaDacProfile (W2-142) and
/// New-DbaDbMaskingConfig (W2-145), where the same "+=" shape targeted plain locals and DID carry.
/// Confirmed mechanically as well as by reading: migration/tools/Find-AccumulatorCarry.ps1 reports
/// zero accumulator candidates. $newSchema (:130) and the loop variables $db and $sName are each
/// assigned before use within their own iteration.
///
/// FOUR Test-Bound SITES BECOME CARRIED CALLER-BOUNDNESS FLAGS (Test-Bound never rides a hop):
/// Schema (:106), SqlInstance and Database (:111), and SchemaOwner (:132). SchemaOwner is the one
/// worth noting: it has NO default, yet is Test-Bound gated, so $newSchema.Owner is assigned ONLY
/// when the caller passed the parameter explicitly. Passing an explicit empty string must therefore
/// still count as bound, which is why the flag comes from MyInvocation.BoundParameters and not from
/// a null/empty test on the property - those two differ exactly when a caller passes "".
///
/// STREAMING, NOT BUFFERED (DEF-001): schemas are created one at a time and each is emitted, so a
/// buffered hop would discard the record of schemas already created when a later failure terminated
/// the hop under -EnableException.
///
/// The one $Pscmdlet.ShouldProcess gate at :128 routes to the real cmdlet via $__realCmdlet. The two
/// in-loop Stop-Function calls (:125 schema exists, :139 create failure) carry -Continue, so they
/// skip that schema and keep looping - and because PowerShell's continue is dynamically scoped, they
/// skip the remainder of the caller's iteration too (measured, logs/probe-20260718-continue-propagation).
/// EnableException crosses as a SwitchParameter OBJECT received untyped, per B's combined rule.
/// In-hop Stop-Function calls carry -FunctionName. Implicit positions 0-5 are made explicit per the
/// W2-071 law and were CONFIRMED against the exported baseline rather than inferred from a position
/// dump - the W2-141 lesson. Surface pinned by migration/baselines/New-DbaDbSchema.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbSchema", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbSchemaCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the schema is created in.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The name(s) of the schema(s) to create.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Schema { get; set; }

    /// <summary>The schema owner; applied only when explicitly passed.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? SchemaOwner { get; set; }

    /// <summary>Databases piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {

        // Streaming, not buffered (DEF-001): schemas are created and emitted one at a time, so a
        // buffered hop would drop the audit trail of schemas already created.
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
            SqlInstance, SqlCredential, Database, Schema, SchemaOwner, InputObject,
            EnableException,
            MyInvocation.BoundParameters.ContainsKey("Schema"),
            MyInvocation.BoundParameters.ContainsKey("SqlInstance"),
            MyInvocation.BoundParameters.ContainsKey("Database"),
            MyInvocation.BoundParameters.ContainsKey("SchemaOwner"),
            this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM, dot-sourced so its two early returns exit only the body and
    // not the whole hop. Edits: the four Test-Bound probes become carried caller-boundness flags,
    // the one $Pscmdlet gate routes to $__realCmdlet, and -FunctionName is stamped on the four
    // Stop-Function calls. NO sentinel epilogue: this source never reads the interrupt latch back
    // (no Test-FunctionInterrupt), so its guards must re-warn per record exactly as they do here.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Schema, $SchemaOwner, $InputObject, $EnableException, $__boundSchema, $__boundSqlInstance, $__boundDatabase, $__boundSchemaOwner, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Schema, [string]$SchemaOwner, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundSchema, $__boundSqlInstance, $__boundDatabase, $__boundSchemaOwner, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {

        if (-not $__boundSchema) {
            Stop-Function -Message "Schema is required" -FunctionName New-DbaDbSchema
            return
        }

        if (($__boundSqlInstance) -and (-not $__boundDatabase)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName New-DbaDbSchema
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {

            foreach ($sName in $Schema) {

                if ($db.Schemas.Name -contains $sName) {
                    Stop-Function -Message "Schema $sName already exists in the database $($db.Name) on $($db.Parent.Name)" -Continue -FunctionName New-DbaDbSchema
                }

                if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Creating the schema $sName on the database $($db.Name)")) {
                    try {
                        $newSchema = New-Object Microsoft.SqlServer.Management.Smo.Schema -ArgumentList $db, $sName

                        if ($__boundSchemaOwner) {
                            $newSchema.Owner = $SchemaOwner
                        }

                        $newSchema.Create()
                        $newSchema
                    } catch {
                        Stop-Function -Message "Failure on $($db.Parent.Name) to create the schema $sName in the database $($db.Name)" -ErrorRecord $_ -Continue -FunctionName New-DbaDbSchema
                    }
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $Schema $SchemaOwner $InputObject $EnableException $__boundSchema $__boundSqlInstance $__boundDatabase $__boundSchemaOwner $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
