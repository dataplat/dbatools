#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoUserDefinedFunction = Microsoft.SqlServer.Management.Smo.UserDefinedFunction;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a T-SQL user-defined function in one or more databases and re-emits the created function decorated like Get-DbaDbUdf.
/// </summary>
/// <remarks>
/// Get-DbaDbUdf existed but there was no way to create a function; this closes that gap. The database resolution,
/// existence check, function creation and output all run a module-scoped PowerShell body inside the dbatools module
/// scope rather than being reimplemented in C#, so the body can call Get-DbaDatabase, Get-DbaDbUdf, Stop-Function
/// and Write-Message directly. Brand-new command with no PowerShell ancestor; the surface is pinned by the
/// owner-signed designed spec and diffed EXACT-match in the gate.
///
/// TEXT HAZARD: the function is created with TextMode FALSE and only TextBody assigned. SMO then synthesises the
/// CREATE header from Schema/Name plus -FunctionType/-DataType (the RETURNS clause for a scalar function) and
/// -SchemaBinding. Assigning TextHeader outside text mode throws, and text mode with a body but no header throws at
/// script time, so the leave-TextMode-false-assign-only-TextBody pattern is the safe one that SetTextBody accepts
/// for a TransactSql object. -Definition carries the function body only (e.g. BEGIN ... RETURN ... END), not a full
/// CREATE statement; it is raw DDL executed verbatim (the same trust class as Invoke-DbaQuery -Query) while every
/// identifier flows through SMO which brackets and quotes it.
///
/// FunctionType and DataType are create-time shape (a scalar function needs its return DataType); they cannot be
/// changed by an ALTER, so Set-DbaDbUdf deliberately does not expose them.
///
/// SAFETY: the sole Create runs only inside a passed $__realCmdlet.ShouldProcess gate, so a -WhatIf run never
/// touches the server. An existing function is refused with a pointer at Set-DbaDbUdf rather than silently altered.
/// Either -SqlInstance or a piped database (the Test-Bound duality, no parameter sets). No cross-record state is
/// carried, so each record runs an independent hop.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbUdf", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(SmoUserDefinedFunction))]
public sealed class NewDbaDbUdfCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the function is created in.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The schema the function belongs to (defaults to dbo).</summary>
    [Parameter(Position = 3)]
    public string? Schema { get; set; }

    /// <summary>The name of the user-defined function to create.</summary>
    [Parameter(Position = 4)]
    public string? Name { get; set; }

    /// <summary>The function body - the T-SQL that follows the RETURNS clause. Not a full CREATE statement.</summary>
    [Parameter(Position = 5)]
    public string? Definition { get; set; }

    /// <summary>The function type (Scalar, Inline, Table). Defaults to Scalar when omitted.</summary>
    [Parameter(Position = 6)]
    public Microsoft.SqlServer.Management.Smo.UserDefinedFunctionType FunctionType { get; set; }

    /// <summary>The return data type for a scalar function.</summary>
    [Parameter(Position = 7)]
    public Microsoft.SqlServer.Management.Smo.DataType? DataType { get; set; }

    /// <summary>Creates the function WITH SCHEMABINDING.</summary>
    [Parameter]
    public SwitchParameter SchemaBinding { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 8)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

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
            FunctionType, DataType, SchemaBinding.ToBool(), InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(FunctionType)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Databases come from -SqlInstance (resolved via Get-DbaDatabase) or piped
    // -InputObject. An existing function is refused (pointing at Set-DbaDbUdf); creation assigns only TextBody with
    // TextMode false so SMO builds the header (RETURNS clause from -FunctionType/-DataType), and runs inside a passed
    // ShouldProcess so -WhatIf never touches the server. The created function is re-emitted via Get-DbaDbUdf so its
    // decoration matches exactly.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Schema, $Name, $Definition, $FunctionType, $DataType, $SchemaBinding, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundFunctionType, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$Schema, [string]$Name, [string]$Definition, $FunctionType, $DataType, $SchemaBinding, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundFunctionType)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName New-DbaDbUdf
        return
    }

    if (-not $Name) {
        Stop-Function -Message "You must specify the function name with -Name" -FunctionName New-DbaDbUdf
        return
    }

    if ($null -eq $Definition) {
        Stop-Function -Message "You must specify the function body with -Definition" -FunctionName New-DbaDbUdf
        return
    }

    if (-not $Schema) { $Schema = "dbo" }

    if ($__boundSqlInstance) {
        try {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -EnableException
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue -FunctionName New-DbaDbUdf
            return
        }
    }

    foreach ($db in $InputObject) {
        $server = $db.Parent

        if (-not $db.IsAccessible) {
            Stop-Function -Message "Database $($db.Name) is not accessible. Skipping." -Target $db -Continue -FunctionName New-DbaDbUdf
            continue
        }

        $existing = $db.UserDefinedFunctions | Where-Object { $_.Name -eq $Name -and $_.Schema -eq $Schema }
        if ($existing) {
            Stop-Function -Message "User-defined function $Schema.$Name already exists in database $($db.Name) on $($server.DomainInstanceName). Use Set-DbaDbUdf to modify it." -Target $db -Continue -FunctionName New-DbaDbUdf
            continue
        }

        if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Creating user-defined function $Schema.$Name in database $($db.Name)")) {
            try {
                $udf = New-Object Microsoft.SqlServer.Management.Smo.UserDefinedFunction -ArgumentList $db, $Name, $Schema
                $udf.TextMode = $false
                if ($__boundFunctionType) { $udf.FunctionType = $FunctionType }
                if ($null -ne $DataType) { $udf.DataType = $DataType }
                if ($SchemaBinding) { $udf.IsSchemaBound = $true }
                $udf.TextBody = $Definition
                $udf.Create()
                $udf.Refresh()
            } catch {
                Stop-Function -Message "Failed to create user-defined function $Schema.$Name in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $db -Continue -FunctionName New-DbaDbUdf
                continue
            }

            Get-DbaDbUdf -SqlInstance $server -Database $db.Name -Name $Name -Schema $Schema
        }
    }
} $SqlInstance $SqlCredential $Database $Schema $Name $Definition $FunctionType $DataType $SchemaBinding $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundFunctionType @__commonParameters 3>&1 2>&1
""";
}
