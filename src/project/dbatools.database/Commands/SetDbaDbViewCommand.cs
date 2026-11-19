#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoView = Microsoft.SqlServer.Management.Smo.View;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Replaces the body of an existing T-SQL view in one or more databases and re-emits the altered view decorated
/// like Get-DbaDbView.
/// </summary>
/// <remarks>
/// Get-DbaDbView and Remove-DbaDbView existed but there was no way to alter a view's definition; this closes that
/// gap. The view resolution, the system-object guard, the alter and the output all run a module-scoped PowerShell
/// body inside the dbatools module scope rather than being reimplemented in C#, so the body can call Get-DbaDbView,
/// Stop-Function and Write-Message directly. Brand-new command with no PowerShell ancestor; the surface is pinned
/// by the owner-signed designed spec and diffed EXACT-match in the gate.
///
/// TEXT HAZARD: only TextBody is assigned with TextMode left FALSE, so SMO regenerates the ALTER header from the
/// view's own Schema/Name plus its already-fetched header options (schema binding / encryption are preserved
/// because they are never touched). Assigning TextHeader outside text mode throws, and text mode with a body but
/// no header throws at script time, so the leave-TextMode-false-assign-only-TextBody pattern is the safe one.
/// -Definition carries the SELECT body only; it is raw DDL executed verbatim (the same trust class as
/// Invoke-DbaQuery -Query) while every identifier flows through SMO which brackets and quotes it.
///
/// SAFETY: the sole Alter runs only inside a passed $__realCmdlet.ShouldProcess gate, so a -WhatIf run never
/// touches the server. IsSystemObject targets are refused unconditionally (no -Force) because rewriting a system
/// view is not something dbatools should make easy. Either -SqlInstance or a piped view (the Test-Bound duality,
/// no parameter sets). A target must be explicit: with -SqlInstance you must also name views with -View, or pipe
/// them in as -InputObject - an unfiltered instance-wide alter that would silently rewrite every view is refused,
/// and ConfirmImpact is High to match Remove-DbaDbView, since replacing N view bodies is as destructive as a drop.
/// No cross-record state is carried, so each record runs an independent hop.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaDbView", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(SmoView))]
public sealed class SetDbaDbViewCommand : DbaBaseCmdlet
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

    /// <summary>Filter to views in the specified schema(s).</summary>
    [Parameter(Position = 3)]
    public string[]? Schema { get; set; }

    /// <summary>The view(s) to alter, by (optionally schema-qualified) name.</summary>
    [Parameter(Position = 4)]
    public string[]? View { get; set; }

    /// <summary>The replacement view body - the SELECT that follows AS. Not a full ALTER statement.</summary>
    [Parameter(Position = 5)]
    public string? Definition { get; set; }

    /// <summary>View object(s) piped in from Get-DbaDbView.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoView[]? InputObject { get; set; }

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
            SqlInstance, SqlCredential, Database, Schema, View, Definition,
            InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(View)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Views come from -SqlInstance (resolved live via Get-DbaDbView, filtered by
    // -Database/-View/-Schema) or piped -InputObject. A target must be explicit - with -SqlInstance the caller
    // must also name views with -View, otherwise the unfiltered instance-wide alter is refused. System views are
    // refused; the alter assigns only TextBody
    // with TextMode false so SMO rebuilds the header, and runs inside a passed ShouldProcess so -WhatIf never
    // touches the server. Each altered view is re-emitted via Get-DbaDbView (Refresh first) so its decoration
    // matches exactly and DateLastModified reflects the alter.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Schema, $View, $Definition, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundView, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Schema, [string[]]$View, [string]$Definition, [Microsoft.SqlServer.Management.Smo.View[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundView)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaDbView
        return
    }

    if (-not $__boundView -and -not $__boundInputObject) {
        Stop-Function -Message "You must specify the target view(s) to alter with -View, or pipe them in as -InputObject. An unfiltered instance-wide alter is not permitted." -FunctionName Set-DbaDbView
        return
    }

    if ($null -eq $Definition) {
        Stop-Function -Message "You must specify the replacement view body with -Definition" -FunctionName Set-DbaDbView
        return
    }

    $viewsToProcess = New-Object System.Collections.Generic.List[object]

    if ($__boundInputObject) {
        foreach ($piped in $InputObject) { $viewsToProcess.Add($piped) }
    }

    if ($__boundSqlInstance) {
        foreach ($instance in $SqlInstance) {
            try {
                $found = Get-DbaDbView -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -View $View -Schema $Schema -EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbView
                continue
            }
            foreach ($f in $found) { $viewsToProcess.Add($f) }
        }
    }

    foreach ($currentView in $viewsToProcess) {
        $db = $currentView.Parent
        $server = $db.Parent

        if ($currentView.IsSystemObject) {
            Stop-Function -Message "View $($currentView.Schema).$($currentView.Name) in database $($db.Name) is a system object and will not be altered." -Target $currentView -Continue -FunctionName Set-DbaDbView
            continue
        }

        if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Altering view $($currentView.Schema).$($currentView.Name) in database $($db.Name)")) {
            try {
                $currentView.TextMode = $false
                $currentView.TextBody = $Definition
                $currentView.Alter()
                $currentView.Refresh()
            } catch {
                Stop-Function -Message "Failed to alter view $($currentView.Schema).$($currentView.Name) in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $currentView -Continue -FunctionName Set-DbaDbView
                continue
            }

            # Filter the re-emit client-side rather than passing a rebuilt "schema.name" string back through
            # Get-DbaDbView's -View parser: that parser splits on dots and requires [ ] wrapping for special
            # characters, so a schema or view name containing a dot or a bracket would resolve to the wrong
            # object or to nothing at all - the alter would succeed but the command would emit garbage.
            Get-DbaDbView -SqlInstance $server -Database $db.Name |
                Where-Object { $_.Schema -eq $currentView.Schema -and $_.Name -eq $currentView.Name }
        }
    }
} $SqlInstance $SqlCredential $Database $Schema $View $Definition $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundView @__commonParameters 3>&1 2>&1
""";
}
