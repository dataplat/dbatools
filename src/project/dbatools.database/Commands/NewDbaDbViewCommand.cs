#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoView = Microsoft.SqlServer.Management.Smo.View;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a T-SQL view in one or more databases and re-emits the created view decorated like Get-DbaDbView.
/// </summary>
/// <remarks>
/// Get-DbaDbView and Remove-DbaDbView existed but there was no way to create a view; this closes that gap.
/// The database resolution, existence check, view creation and output all run a module-scoped PowerShell body
/// inside the dbatools module scope rather than being reimplemented in C#, so the body can call Get-DbaDatabase,
/// Get-DbaDbView, Stop-Function and Write-Message directly. Brand-new command with no PowerShell ancestor; the
/// surface is pinned by the owner-signed designed spec and diffed EXACT-match in the gate.
///
/// TEXT HAZARD: the view is created with TextMode FALSE and only TextBody assigned. SMO then synthesises the
/// CREATE header from Schema/Name plus the header options (-SchemaBinding -> IsSchemaBound, -Encryption ->
/// IsEncrypted). Assigning TextHeader outside text mode throws, and text mode with a body but no header throws
/// at script time, so the leave-TextMode-false-assign-only-TextBody pattern is the safe one. -Definition carries
/// the SELECT body only, not a full CREATE statement; it is raw DDL executed verbatim (the same trust class as
/// Invoke-DbaQuery -Query) while every identifier flows through SMO which brackets and quotes it.
///
/// SAFETY: the sole Create runs only inside a passed $__realCmdlet.ShouldProcess gate, so a -WhatIf run never
/// touches the server. An existing view is refused with a pointer at Set-DbaDbView rather than silently altered.
/// Either -SqlInstance or a piped database (the Test-Bound duality, no parameter sets). No cross-record state is
/// carried, so each record runs an independent hop.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbView", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(SmoView))]
public sealed class NewDbaDbViewCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the view is created in.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The schema the view belongs to (defaults to dbo).</summary>
    [Parameter(Position = 3)]
    public string? Schema { get; set; }

    /// <summary>The name of the view to create.</summary>
    [Parameter(Position = 4)]
    public string? Name { get; set; }

    /// <summary>The view body - the SELECT that follows AS. Not a full CREATE statement.</summary>
    [Parameter(Position = 5)]
    public string? Definition { get; set; }

    /// <summary>Creates the view WITH ENCRYPTION.</summary>
    [Parameter]
    public SwitchParameter Encryption { get; set; }

    /// <summary>Creates the view WITH SCHEMABINDING.</summary>
    [Parameter]
    public SwitchParameter SchemaBinding { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
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
            Encryption.ToBool(), SchemaBinding.ToBool(), InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Databases come from -SqlInstance (resolved via Get-DbaDatabase) or piped
    // -InputObject. An existing view is refused (pointing at Set-DbaDbView); creation assigns only TextBody with
    // TextMode false so SMO builds the header, and runs inside a passed ShouldProcess so -WhatIf never touches the
    // server. The created view is re-emitted via Get-DbaDbView so its decoration matches exactly.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Schema, $Name, $Definition, $Encryption, $SchemaBinding, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$Schema, [string]$Name, [string]$Definition, $Encryption, $SchemaBinding, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName New-DbaDbView
        return
    }

    if (-not $Name) {
        Stop-Function -Message "You must specify the view name with -Name" -FunctionName New-DbaDbView
        return
    }

    if ($null -eq $Definition) {
        Stop-Function -Message "You must specify the view body with -Definition" -FunctionName New-DbaDbView
        return
    }

    if (-not $Schema) { $Schema = "dbo" }

    if ($__boundSqlInstance) {
        try {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -EnableException
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue -FunctionName New-DbaDbView
            return
        }
    }

    foreach ($db in $InputObject) {
        $server = $db.Parent

        if (-not $db.IsAccessible) {
            Stop-Function -Message "Database $($db.Name) is not accessible. Skipping." -Target $db -Continue -FunctionName New-DbaDbView
            continue
        }

        $existing = $db.Views | Where-Object { $_.Name -eq $Name -and $_.Schema -eq $Schema }
        if ($existing) {
            Stop-Function -Message "View $Schema.$Name already exists in database $($db.Name) on $($server.DomainInstanceName). Use Set-DbaDbView to modify it." -Target $db -Continue -FunctionName New-DbaDbView
            continue
        }

        if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Creating view $Schema.$Name in database $($db.Name)")) {
            try {
                $view = New-Object Microsoft.SqlServer.Management.Smo.View -ArgumentList $db, $Name, $Schema
                $view.TextMode = $false
                if ($SchemaBinding) { $view.IsSchemaBound = $true }
                if ($Encryption) { $view.IsEncrypted = $true }
                $view.TextBody = $Definition
                $view.Create()
                $view.Refresh()
            } catch {
                Stop-Function -Message "Failed to create view $Schema.$Name in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $db -Continue -FunctionName New-DbaDbView
                continue
            }

            Get-DbaDbView -SqlInstance $server -Database $db.Name -View "$Schema.$Name"
        }
    }
} $SqlInstance $SqlCredential $Database $Schema $Name $Definition $Encryption $SchemaBinding $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject @__commonParameters 3>&1 2>&1
""";
}
