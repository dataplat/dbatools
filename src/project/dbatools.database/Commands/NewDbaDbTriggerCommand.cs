#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoDatabaseDdlTrigger = Microsoft.SqlServer.Management.Smo.DatabaseDdlTrigger;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a database-scoped DDL trigger in one or more databases and re-emits the created trigger decorated
/// like Get-DbaDbTrigger.
/// </summary>
/// <remarks>
/// Get-DbaDbTrigger and Remove-DbaDbTrigger existed but there was no way to create a DDL trigger; this closes
/// that gap. The database resolution, existence check, trigger creation and output all run a module-scoped
/// PowerShell body inside the dbatools module scope rather than being reimplemented in C#, so the body can call
/// Get-DbaDatabase, Get-DbaDbTrigger, Stop-Function and Write-Message directly. Brand-new command with no
/// PowerShell ancestor; the surface is pinned by the owner-signed designed spec and diffed EXACT-match in the
/// gate.
///
/// SCOPE: database-scoped DDL triggers only (the scope Get-DbaDbTrigger enumerates, Database.Triggers). INSTEAD
/// OF and DML table triggers are out of v1, and DDL triggers are not schema-scoped so there is no -Schema.
///
/// TEXT HAZARD: the trigger is created from the two-argument DatabaseDdlTrigger(database, name) constructor, then
/// its DdlTriggerEvents set, TextMode (left FALSE) and TextBody are assigned as separate properties before
/// Create(). Only TextBody is assigned with TextMode false, so SMO synthesises the CREATE header from the name
/// plus the DDL event set. Assigning TextHeader outside text mode throws, and text mode with a body but no header
/// throws at script time, so the leave-TextMode-false-assign-only-TextBody pattern is the safe one. -Definition carries the trigger
/// body only, not a full CREATE statement; it is raw DDL executed verbatim (the same trust class as
/// Invoke-DbaQuery -Query) while every identifier flows through SMO which brackets and quotes it.
///
/// EVENT SET: -DdlEvent is String[] of DDL event names (the DatabaseDdlTriggerEventSet boolean member names,
/// e.g. CreateTable, AlterTable, DropTable). The concrete set type is codegen output and cannot be enumerated
/// from source, so the parameter validates each name against the set's writable boolean members and
/// StopFunctions on an unknown one. At least one event is required.
///
/// SAFETY: the sole Create runs only inside a passed $__realCmdlet.ShouldProcess gate, so a -WhatIf run never
/// touches the server. An existing trigger is refused with a pointer at Set-DbaDbTrigger rather than silently
/// altered. Either -SqlInstance or a piped database (the Test-Bound duality, no parameter sets). Scope must be
/// explicit: with -SqlInstance the caller must also name databases with -Database, or pipe them in as
/// -InputObject - an unscoped instance-wide create that would deploy the trigger into every database (including
/// model, propagating to all future databases) is refused. ConfirmImpact is High because that create walks
/// system databases. No cross-record state is carried, so each record runs an independent hop.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbTrigger", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(SmoDatabaseDdlTrigger))]
public sealed class NewDbaDbTriggerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the DDL trigger is created in.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The name of the DDL trigger to create.</summary>
    [Parameter(Position = 3)]
    public string? Name { get; set; }

    /// <summary>The trigger body - the statements that follow AS. Not a full CREATE statement.</summary>
    [Parameter(Position = 4)]
    public string? Definition { get; set; }

    /// <summary>The DDL event(s) the trigger fires on (e.g. CreateTable, AlterTable, DropTable). At least one.</summary>
    [Parameter(Position = 5)]
    public string[]? DdlEvent { get; set; }

    /// <summary>Creates the trigger enabled (default) or, with -IsEnabled:$false, disabled.</summary>
    [Parameter]
    public SwitchParameter IsEnabled { get; set; }

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
            SqlInstance, SqlCredential, Database, Name, Definition, DdlEvent,
            IsEnabled.ToBool(), InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(IsEnabled)), TestBound(nameof(Database)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Databases come from -SqlInstance (resolved via Get-DbaDatabase, filtered by
    // -Database) or piped -InputObject. Scope must be explicit - with -SqlInstance the caller must also name
    // databases with -Database, otherwise the unscoped instance-wide create is refused. The -DdlEvent names are
    // validated against the DatabaseDdlTriggerEventSet writable boolean members and mapped onto a fresh set per
    // database. An existing trigger is refused (pointing at Set-DbaDbTrigger); creation uses the two-arg
    // constructor then assigns DdlTriggerEvents, TextMode false and TextBody so SMO builds the header, and runs
    // inside a passed ShouldProcess so -WhatIf never touches the server. The created trigger is re-emitted via
    // Get-DbaDbTrigger (filtered by name) so its decoration matches exactly.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Name, $Definition, $DdlEvent, $IsEnabled, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundIsEnabled, $__boundDatabase, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$Name, [string]$Definition, [string[]]$DdlEvent, $IsEnabled, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundIsEnabled, $__boundDatabase)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName New-DbaDbTrigger
        return
    }

    if (-not $__boundDatabase -and -not $__boundInputObject) {
        Stop-Function -Message "You must specify the target database(s) with -Database, or pipe them in as -InputObject. An unscoped instance-wide create is not permitted." -FunctionName New-DbaDbTrigger
        return
    }

    if (-not $Name) {
        Stop-Function -Message "You must specify the trigger name with -Name" -FunctionName New-DbaDbTrigger
        return
    }

    if ($null -eq $Definition) {
        Stop-Function -Message "You must specify the trigger body with -Definition" -FunctionName New-DbaDbTrigger
        return
    }

    if (-not $DdlEvent) {
        Stop-Function -Message "You must specify at least one DDL event with -DdlEvent" -FunctionName New-DbaDbTrigger
        return
    }

    # Validate the requested event names against the DatabaseDdlTriggerEventSet writable boolean members once.
    # The set type is codegen output, so the writable bool members ARE the event vocabulary; Dirty is bookkeeping.
    $probeSet = New-Object Microsoft.SqlServer.Management.Smo.DatabaseDdlTriggerEventSet
    $validEvents = $probeSet.GetType().GetProperties() | Where-Object { $_.PropertyType -eq [bool] -and $_.CanWrite -and $_.Name -ne "Dirty" } | Select-Object -ExpandProperty Name
    $resolvedEvents = @()
    foreach ($evt in $DdlEvent) {
        $match = $validEvents | Where-Object { $_ -eq $evt } | Select-Object -First 1
        if (-not $match) {
            Stop-Function -Message "Unknown DDL event `"$evt`". Valid events are members of DatabaseDdlTriggerEventSet (for example CreateTable, AlterTable, DropTable, DdlDatabaseLevelEventsEvents)." -Target $evt -FunctionName New-DbaDbTrigger
            return
        }
        $resolvedEvents += $match
    }

    if ($__boundSqlInstance) {
        try {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -EnableException
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName New-DbaDbTrigger
            return
        }
    }

    foreach ($db in $InputObject) {
        $server = $db.Parent

        if (-not $db.IsAccessible) {
            Stop-Function -Message "Database $($db.Name) is not accessible. Skipping." -Target $db -Continue -FunctionName New-DbaDbTrigger
            continue
        }

        $existing = $db.Triggers | Where-Object { $_.Name -eq $Name }
        if ($existing) {
            Stop-Function -Message "DDL trigger $Name already exists in database $($db.Name) on $($server.DomainInstanceName). Use Set-DbaDbTrigger to modify it." -Target $db -Continue -FunctionName New-DbaDbTrigger
            continue
        }

        if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Creating DDL trigger $Name in database $($db.Name)")) {
            try {
                $eventSet = New-Object Microsoft.SqlServer.Management.Smo.DatabaseDdlTriggerEventSet
                foreach ($n in $resolvedEvents) { $eventSet.$n = $true }
                $trigger = New-Object Microsoft.SqlServer.Management.Smo.DatabaseDdlTrigger -ArgumentList $db, $Name
                # Leave TextMode FALSE and assign only TextBody so SMO synthesises the CREATE header (name + FOR
                # <events>); assigning TextHeader outside text mode throws, and text mode with a body but no header
                # throws at script time.
                $trigger.TextMode = $false
                $trigger.DdlTriggerEvents = $eventSet
                if ($__boundIsEnabled) { $trigger.IsEnabled = [bool]$IsEnabled }
                $trigger.TextBody = $Definition
                $trigger.Create()
                $trigger.Refresh()
            } catch {
                Stop-Function -Message "Failed to create DDL trigger $Name in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $db -Continue -FunctionName New-DbaDbTrigger
                continue
            }

            Get-DbaDbTrigger -SqlInstance $server -Database $db.Name | Where-Object { $_.Name -eq $Name }
        }
    }
} $SqlInstance $SqlCredential $Database $Name $Definition $DdlEvent $IsEnabled $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundIsEnabled $__boundDatabase @__commonParameters 3>&1 2>&1
""";
}
