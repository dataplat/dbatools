#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoStoredProcedure = Microsoft.SqlServer.Management.Smo.StoredProcedure;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Replaces the body of an existing T-SQL stored procedure in one or more databases and re-emits the altered
/// procedure decorated like Get-DbaDbStoredProcedure.
/// </summary>
/// <remarks>
/// Get-DbaDbStoredProcedure existed but there was no way to alter a procedure's definition; this closes that gap.
/// The procedure resolution, the system-object guard, the CLR guard, the alter and the output all run a
/// module-scoped PowerShell body inside the dbatools module scope rather than being reimplemented in C#, so the
/// body can call Get-DbaDbStoredProcedure, Stop-Function and Write-Message directly. Brand-new command with no
/// PowerShell ancestor; the surface is pinned by the owner-signed designed spec and diffed EXACT-match in the gate.
///
/// TEXT HAZARD: only TextBody is assigned with TextMode left FALSE, so SMO regenerates the ALTER header from the
/// procedure's own Schema/Name plus its already-fetched header options (schema binding / encryption are preserved
/// because they are never touched). Assigning TextHeader outside text mode throws, and text mode with a body but no
/// header throws at script time, so the leave-TextMode-false-assign-only-TextBody pattern is the safe one.
/// -Definition carries the procedure body only; it is raw DDL executed verbatim (the same trust class as
/// Invoke-DbaQuery -Query) while every identifier flows through SMO which brackets and quotes it.
///
/// CLR GUARD: a CLR (SqlClr) procedure has no editable text body, so it is refused per item with a clear message
/// BEFORE anything is assigned. The check reads ImplementationType directly rather than relying on catching SMO's
/// NoPropertyChangeForDotNet exception, because that exception is not raised on Azure SQL Database nor when TextMode
/// is true - checking the property behaves identically everywhere.
///
/// SAFETY: the sole Alter runs only inside a passed $__realCmdlet.ShouldProcess gate, so a -WhatIf run never touches
/// the server. IsSystemObject targets are refused unconditionally (no -Force). Either -SqlInstance or a piped
/// procedure (the Test-Bound duality, no parameter sets). No cross-record state is carried, so each record runs an
/// independent hop.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaDbStoredProcedure", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(SmoStoredProcedure))]
public sealed class SetDbaDbStoredProcedureCommand : DbaBaseCmdlet
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

    /// <summary>Filter to procedures in the specified schema(s).</summary>
    [Parameter(Position = 3)]
    public string[]? Schema { get; set; }

    /// <summary>The stored procedure(s) to alter, by name.</summary>
    [Parameter(Position = 4)]
    public string[]? Name { get; set; }

    /// <summary>The replacement procedure body - the T-SQL that follows AS. Not a full ALTER statement.</summary>
    [Parameter(Position = 5)]
    public string? Definition { get; set; }

    /// <summary>Stored procedure object(s) piped in from Get-DbaDbStoredProcedure.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoStoredProcedure[]? InputObject { get; set; }

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

    // PS: the module-scoped body. Procedures come from -SqlInstance (resolved live via Get-DbaDbStoredProcedure,
    // filtered by -Database/-Name/-Schema) or piped -InputObject. System procedures and CLR procedures are refused;
    // the alter assigns only TextBody with TextMode false so SMO rebuilds the header, and runs inside a passed
    // ShouldProcess so -WhatIf never touches the server. Each altered procedure is re-emitted via
    // Get-DbaDbStoredProcedure (Refresh first) so its decoration matches exactly and DateLastModified reflects the alter.
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
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Schema, [string[]]$Name, [string]$Definition, [Microsoft.SqlServer.Management.Smo.StoredProcedure[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaDbStoredProcedure
        return
    }

    if ($null -eq $Definition) {
        Stop-Function -Message "You must specify the replacement stored procedure body with -Definition" -FunctionName Set-DbaDbStoredProcedure
        return
    }

    $proceduresToProcess = New-Object System.Collections.Generic.List[object]

    if ($__boundInputObject) {
        foreach ($piped in $InputObject) { $proceduresToProcess.Add($piped) }
    }

    if ($__boundSqlInstance) {
        foreach ($instance in $SqlInstance) {
            try {
                $found = Get-DbaDbStoredProcedure -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -Name $Name -Schema $Schema -EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbStoredProcedure
                continue
            }
            foreach ($f in $found) { $proceduresToProcess.Add($f) }
        }
    }

    foreach ($currentProcedure in $proceduresToProcess) {
        $db = $currentProcedure.Parent
        $server = $db.Parent

        if ($currentProcedure.IsSystemObject) {
            Stop-Function -Message "Stored procedure $($currentProcedure.Schema).$($currentProcedure.Name) in database $($db.Name) is a system object and will not be altered." -Target $currentProcedure -Continue -FunctionName Set-DbaDbStoredProcedure
            continue
        }

        if ($currentProcedure.ImplementationType -eq [Microsoft.SqlServer.Management.Smo.ImplementationType]::SqlClr) {
            Stop-Function -Message "Stored procedure $($currentProcedure.Schema).$($currentProcedure.Name) in database $($db.Name) is a CLR procedure and has no editable text body. Use Invoke-DbaQuery to redeploy the assembly." -Target $currentProcedure -Continue -FunctionName Set-DbaDbStoredProcedure
            continue
        }

        if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Altering stored procedure $($currentProcedure.Schema).$($currentProcedure.Name) in database $($db.Name)")) {
            try {
                $currentProcedure.TextMode = $false
                $currentProcedure.TextBody = $Definition
                $currentProcedure.Alter()
                $currentProcedure.Refresh()
            } catch {
                Stop-Function -Message "Failed to alter stored procedure $($currentProcedure.Schema).$($currentProcedure.Name) in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $currentProcedure -Continue -FunctionName Set-DbaDbStoredProcedure
                continue
            }

            Get-DbaDbStoredProcedure -SqlInstance $server -Database $db.Name -Name $currentProcedure.Name -Schema $currentProcedure.Schema
        }
    }
} $SqlInstance $SqlCredential $Database $Schema $Name $Definition $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject @__commonParameters 3>&1 2>&1
""";
}
