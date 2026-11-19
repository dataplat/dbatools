#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Changes the owner of a database schema. Port of public/Set-DbaDbSchema.ps1; the workflow remains
/// a module-scoped PowerShell compatibility hop.
///
/// Test-Bound cannot ride the hop - it inspects the CALLER's bound parameters, and inside a hop the
/// caller is the scriptblock rather than this cmdlet, so the guard would never fire. Both call sites
/// are flag-substituted and evaluated here.
///
/// The ShouldProcess gate is routed to the OUTER cmdlet ($Pscmdlet becomes $__realCmdlet). Beyond
/// attribution, -Confirm's "Yes to All" answer is held on the invoking runtime, so a gate owned by
/// the inner scriptblock would forget it between pipeline records and re-prompt for every schema.
///
/// NO graceful-stop latch is carried here, and that is a deliberate reading rather than an
/// omission. The latch matters when a source SETS a stop (a Stop-Function without -Continue) and
/// then READS it on a later record through a Test-FunctionInterrupt guard. This source has no such
/// guard: after its one hard Stop-Function returns from a record, the next record simply re-enters
/// the process body and re-evaluates the same condition, warning again. Carrying a latch would
/// therefore SUPPRESS a warning the script function actually repeats. Verified by measurement
/// rather than inferred - see the per-record warning counts in the row evidence.
///
/// The hop stays WHOLE-ARRAY rather than splitting per instance: the instance loop exists only to
/// accumulate into $InputObject, which is cross-instance state and the per-element ruling's stated
/// exemption.
///
/// No local needs a cross-record carry. $InputObject is re-bound from the pipeline on every record
/// before the accumulation runs, and $instance, $db, $sName and $schemaObject are each assigned and
/// read within one iteration.
///
/// The hop streams rather than buffers. This command MUTATES server state and each emitted object
/// records a schema whose owner was actually changed, so a buffered invocation would discard the
/// records of already-altered schemas if a later one threw under -EnableException.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbSchema", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(PSObject))]
public sealed class SetDbaDbSchemaCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases holding the schema.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The schema or schemas to update.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    public string[]? Schema { get; set; }

    /// <summary>The login that will own the schema.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [PsStringCast]
    public string? SchemaOwner { get; set; }

    /// <summary>SMO database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(Position = 5, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {

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
            SqlInstance, SqlCredential, Database, Schema, SchemaOwner, InputObject,
            EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet, the
    // two Test-Bound call sites -> flags computed on the C# side, and -FunctionName on Stop-Function.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Schema, $SchemaOwner, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundDatabase, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Schema, [string]$SchemaOwner, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundDatabase, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }


        if ($__boundSqlInstance -and (-not $__boundDatabase)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Set-DbaDbSchema
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {

            foreach ($sName in $Schema) {

                if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Updating the schema $sName on the database $($db.Name) to be owned by $SchemaOwner")) {
                    try {
                        $schemaObject = $db | Get-DbaDbSchema -Schema $sName
                        $schemaObject.Owner = $SchemaOwner
                        $schemaObject.Alter()
                        $schemaObject
                    } catch {
                        Stop-Function -Message "Failure on $($db.Parent.Name) to update the schema owner for $sName in the database $($db.Name)" -ErrorRecord $_ -Continue -FunctionName Set-DbaDbSchema
                    }
                }
            }
        }

} $SqlInstance $SqlCredential $Database $Schema $SchemaOwner $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundDatabase $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
