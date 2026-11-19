#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoUserDefinedFunction = Microsoft.SqlServer.Management.Smo.UserDefinedFunction;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Replaces the body of an existing T-SQL user-defined function in one or more databases and re-emits the altered
/// function decorated like Get-DbaDbUdf.
/// </summary>
/// <remarks>
/// Get-DbaDbUdf existed but there was no way to alter a function's definition; this closes that gap. The function
/// resolution, the system-object guard, the alter and the output all run a module-scoped PowerShell body inside the
/// dbatools module scope rather than being reimplemented in C#, so the body can call Get-DbaDbUdf, Stop-Function and
/// Write-Message directly. Brand-new command with no PowerShell ancestor; the surface is pinned by the owner-signed
/// designed spec and diffed EXACT-match in the gate.
///
/// TEXT HAZARD: only TextBody is assigned with TextMode left FALSE, so SMO regenerates the ALTER header from the
/// function's own Schema/Name plus its already-fetched header shape (return type / schema binding are preserved
/// because they are never touched). Assigning TextHeader outside text mode throws, and text mode with a body but no
/// header throws at script time, so the leave-TextMode-false-assign-only-TextBody pattern is the safe one.
/// -Definition carries the function body only; it is raw DDL executed verbatim (the same trust class as
/// Invoke-DbaQuery -Query) while every identifier flows through SMO which brackets and quotes it.
///
/// SCOPE: -InputObject is typed Smo.UserDefinedFunction[] precisely so a piped UserDefinedAggregate (which
/// Get-DbaDbUdf also emits) will not bind - aggregates are CLR and have no editable text body. Signature changes
/// (return type / function type) are not expressible by an ALTER, so this command does not expose them; the help
/// documents drop-and-recreate for those.
///
/// SAFETY: the sole Alter runs only inside a passed $__realCmdlet.ShouldProcess gate, so a -WhatIf run never touches
/// the server. IsSystemObject targets are refused unconditionally (no -Force). Either -SqlInstance or a piped
/// function (the Test-Bound duality, no parameter sets). No cross-record state is carried, so each record runs an
/// independent hop.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaDbUdf", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(SmoUserDefinedFunction))]
public sealed class SetDbaDbUdfCommand : DbaBaseCmdlet
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

    /// <summary>Filter to functions in the specified schema(s).</summary>
    [Parameter(Position = 3)]
    public string[]? Schema { get; set; }

    /// <summary>The user-defined function(s) to alter, by name.</summary>
    [Parameter(Position = 4)]
    public string[]? Name { get; set; }

    /// <summary>The replacement function body - the T-SQL that follows the RETURNS clause. Not a full ALTER statement.</summary>
    [Parameter(Position = 5)]
    public string? Definition { get; set; }

    /// <summary>Function object(s) piped in from Get-DbaDbUdf.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoUserDefinedFunction[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the designed spec declares it in __AllParameterSets.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

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
            SqlInstance, SqlCredential, Database, Schema, Name, Definition,
            InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Functions come from -SqlInstance (resolved live via Get-DbaDbUdf, filtered by
    // -Database/-Name/-Schema) or piped -InputObject. System functions are refused; the alter assigns only TextBody
    // with TextMode false so SMO rebuilds the header, and runs inside a passed ShouldProcess so -WhatIf never touches
    // the server. Each altered function is re-emitted via Get-DbaDbUdf (Refresh first) so its decoration matches
    // exactly and DateLastModified reflects the alter.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Schema, $Name, $Definition, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Schema, [string[]]$Name, [string]$Definition, [Microsoft.SqlServer.Management.Smo.UserDefinedFunction[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaDbUdf
        return
    }

    if ($null -eq $Definition) {
        Stop-Function -Message "You must specify the replacement function body with -Definition" -FunctionName Set-DbaDbUdf
        return
    }

    $functionsToProcess = New-Object System.Collections.Generic.List[object]

    if ($__boundInputObject) {
        foreach ($piped in $InputObject) { $functionsToProcess.Add($piped) }
    }

    if ($__boundSqlInstance) {
        foreach ($instance in $SqlInstance) {
            try {
                $found = Get-DbaDbUdf -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -Name $Name -Schema $Schema -EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbUdf
                continue
            }
            foreach ($f in $found) { $functionsToProcess.Add($f) }
        }
    }

    foreach ($currentFunction in $functionsToProcess) {
        $db = $currentFunction.Parent
        $server = $db.Parent

        if ($currentFunction.IsSystemObject) {
            Stop-Function -Message "User-defined function $($currentFunction.Schema).$($currentFunction.Name) in database $($db.Name) is a system object and will not be altered." -Target $currentFunction -Continue -FunctionName Set-DbaDbUdf
            continue
        }

        if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Altering user-defined function $($currentFunction.Schema).$($currentFunction.Name) in database $($db.Name)")) {
            try {
                $currentFunction.TextMode = $false
                $currentFunction.TextBody = $Definition
                $currentFunction.Alter()
                $currentFunction.Refresh()
            } catch {
                Stop-Function -Message "Failed to alter user-defined function $($currentFunction.Schema).$($currentFunction.Name) in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $currentFunction -Continue -FunctionName Set-DbaDbUdf
                continue
            }

            Get-DbaDbUdf -SqlInstance $server -Database $db.Name -Name $currentFunction.Name -Schema $currentFunction.Schema
        }
    }
} $SqlInstance $SqlCredential $Database $Schema $Name $Definition $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject @__commonParameters 3>&1 2>&1
""";
}
