#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops schemas from one or more databases. Port of public/Remove-DbaDbSchema.ps1 (W2-166); the
/// workflow remains a module-scoped PowerShell compatibility hop.
///
/// A small process-only port, and deliberately an unremarkable one - after several rows in this
/// descent that needed carries, relocations or synthesis, this body needs none of them and the value
/// is in confirming that rather than reaching for machinery out of habit.
///
/// TWO Test-Bound reads become TWO carried flags:
///     Test-Bound -ParameterName SqlInstance    -> $__boundSqlInstance
///     Test-Bound -Not -ParameterName Database  -> -not $__boundDatabase
/// Both are was-it-SUPPLIED tests and must not become truthiness tests: an explicitly-passed empty
/// -Database still satisfies the guard rather than tripping "Database is required".
///
/// NO state carry of any kind. There is no begin block, no end block, and nothing in the body reads a
/// local before assigning it, so the hop's per-record scope reset cannot change behaviour. The
/// pre-port DEF-012 detector returns clean in BOTH shapes (cross-record and cross-branch), and here
/// - unlike W2-172 and W2-170, where a clean result merely reflected the tool's process-block-only
/// scope - that clean result is genuinely meaningful, because this command has no other block for a
/// carry to hide in.
///
/// NO continue-guard wrapper. The guard exits with a plain `return`, which a return inside the hop
/// scriptblock reproduces, and the single Stop-Function -Continue sits inside a genuine enclosing
/// foreach (over $Schema, itself nested in the foreach over $InputObject).
///
/// $InputObject is APPENDED to (`$InputObject += Get-DbaDatabase ...`) rather than reassigned, so a
/// caller may pipe databases AND name an instance and get both sets - preserved verbatim.
///
/// ShouldProcess is real at HIGH impact, so $Pscmdlet.ShouldProcess becomes
/// $__realCmdlet.ShouldProcess with target and action byte-for-byte, and the hop carries
/// -WhatIf/-Confirm explicitly so a High-impact confirmation behaves as the source's does.
///
/// Only other body edit is -FunctionName Remove-DbaDbSchema on the two direct Stop-Function sites.
///
/// Surface pinned by migration/baselines/Remove-DbaDbSchema.json
/// (sourceSha256 9e4de00396c16c5f8d4b1106d798c0987fe5fb7911c374fe7a928def58d9840d): no named parameter
/// sets; SqlInstance 0, SqlCredential 1, Database 2, Schema 3 MANDATORY, InputObject 4
/// ValueFromPipeline; outputType empty. Positions declared explicitly per the positional-binding-loss
/// class.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbSchema", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbSchemaCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The schema(s) to drop.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    public string[]? Schema { get; set; }

    /// <summary>Database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
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
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, Schema, InputObject, EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)),
            this, NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block verbatim. Edits: the two Test-Bound reads -> carried bound flags,
    // $Pscmdlet -> $__realCmdlet, and -FunctionName Remove-DbaDbSchema on the direct Stop-Function
    // sites.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Schema, $InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Schema, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($__boundSqlInstance -and (-not $__boundDatabase)) {
        Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Remove-DbaDbSchema
        return
    }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
    }

    foreach ($db in $InputObject) {

        foreach ($sName in $Schema) {

            if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Dropping the schema $sName on the database $($db.Name)")) {
                try {
                    $schemaObject = $db | Get-DbaDbSchema -Schema $sName
                    $schemaObject.Drop()
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to drop the schema $sName in the database $($db.Name)" -ErrorRecord $_ -Continue -FunctionName Remove-DbaDbSchema
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $Schema $InputObject $EnableException $__boundSqlInstance $__boundDatabase $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
