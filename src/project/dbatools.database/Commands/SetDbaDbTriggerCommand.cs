#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoDatabaseDdlTrigger = Microsoft.SqlServer.Management.Smo.DatabaseDdlTrigger;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters an existing database-scoped DDL trigger - its body, its event set, or its enabled state - and
/// re-emits the refreshed trigger decorated like Get-DbaDbTrigger.
/// </summary>
/// <remarks>
/// Get-DbaDbTrigger and New-DbaDbTrigger existed but there was no way to modify a DDL trigger; this closes that
/// gap. The trigger resolution, the system-object guard, the CLR guard, the alter and the output all run a
/// module-scoped PowerShell body inside the dbatools module scope rather than being reimplemented in C#, so the
/// body can call Get-DbaDatabase, Get-DbaDbTrigger, Stop-Function and Write-Message directly. Brand-new command
/// with no PowerShell ancestor; the surface is pinned by the owner-signed designed spec and diffed EXACT-match in
/// the gate.
///
/// TWO OPERATIONS, TWO GATES: the body/event change (Alter) and the enable-state toggle are genuinely distinct -
/// SMO scripts ENABLE/DISABLE TRIGGER as its own statement and excludes IsEnabled from the body dirty check - so
/// -IsEnabled alone never rewrites the body. Each carries its own ShouldProcess string, and -IsEnabled is read
/// with Test-Bound so -IsEnabled:$false disables and an unbound switch leaves the state alone.
///
/// TEXT HAZARD: a body change assigns TextBody with TextMode FALSE so SMO synthesises the ALTER header; assigning
/// TextHeader outside text mode throws, and text mode with a body but no header throws at script time.
/// -Definition is raw DDL executed verbatim (the same trust class as Invoke-DbaQuery -Query) while every
/// identifier flows through SMO which brackets and quotes it. -DdlEvent REPLACES the event set wholesale (it is a
/// single set-valued property, not an add/remove collection) and cannot be empty.
///
/// GUARDS: a system-object trigger is refused unconditionally; a CLR (SqlClr) trigger is refused for body/event
/// changes because its text is not editable (an enable-state-only toggle is still allowed). Either -SqlInstance
/// or a piped Get-DbaDbTrigger object (the Test-Bound duality, no parameter sets).
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaDbTrigger", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(SmoDatabaseDdlTrigger))]
public sealed class SetDbaDbTriggerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to look in when resolving triggers by name.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The name(s) of the DDL trigger(s) to alter (on the -SqlInstance path).</summary>
    [Parameter(Position = 3)]
    public string[]? Name { get; set; }

    /// <summary>The replacement trigger body - the statements that follow AS. Not a full CREATE statement.</summary>
    [Parameter(Position = 4)]
    public string? Definition { get; set; }

    /// <summary>The replacement DDL event set (replaces, does not add to, the existing events). Cannot be empty.</summary>
    [Parameter(Position = 5)]
    public string[]? DdlEvent { get; set; }

    /// <summary>Enables (default) or, with -IsEnabled:$false, disables the trigger.</summary>
    [Parameter]
    public SwitchParameter IsEnabled { get; set; }

    /// <summary>DDL trigger object(s) piped in from Get-DbaDbTrigger.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoDatabaseDdlTrigger[]? InputObject { get; set; }

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
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(Name)),
            TestBound(nameof(Definition)), TestBound(nameof(DdlEvent)), TestBound(nameof(IsEnabled)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Triggers come from -SqlInstance (resolved via Get-DbaDbTrigger per database,
    // then filtered by -Name) or piped -InputObject. System and CLR (for body/event changes) triggers are
    // refused. A body/event change assigns TextBody (TextMode false) and/or replaces DdlTriggerEvents under one
    // ShouldProcess; an enable-state toggle is a second, separate ShouldProcess. Each change runs inside a passed
    // gate so -WhatIf never touches the server. The refreshed trigger is re-emitted via Get-DbaDbTrigger.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Name, $Definition, $DdlEvent, $IsEnabled, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundName, $__boundDefinition, $__boundDdlEvent, $__boundIsEnabled, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Name, [string]$Definition, [string[]]$DdlEvent, $IsEnabled, [Microsoft.SqlServer.Management.Smo.DatabaseDdlTrigger[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundName, $__boundDefinition, $__boundDdlEvent, $__boundIsEnabled)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaDbTrigger
        return
    }

    if (-not $__boundDefinition -and -not $__boundDdlEvent -and -not $__boundIsEnabled) {
        Stop-Function -Message "You must specify at least one change: -Definition, -DdlEvent or -IsEnabled" -FunctionName Set-DbaDbTrigger
        return
    }

    if ($__boundDefinition -and $null -eq $Definition) {
        Stop-Function -Message "You must specify the replacement trigger body with -Definition" -FunctionName Set-DbaDbTrigger
        return
    }

    # -DdlEvent replaces the event set wholesale and cannot be empty; validate names against the set's writable
    # bool members (Dirty is bookkeeping) once, up front.
    $resolvedEvents = @()
    if ($__boundDdlEvent) {
        if (-not $DdlEvent) {
            Stop-Function -Message "-DdlEvent cannot be empty; it replaces the trigger's event set." -FunctionName Set-DbaDbTrigger
            return
        }
        $probeSet = New-Object Microsoft.SqlServer.Management.Smo.DatabaseDdlTriggerEventSet
        $validEvents = $probeSet.GetType().GetProperties() | Where-Object { $_.PropertyType -eq [bool] -and $_.CanWrite -and $_.Name -ne "Dirty" } | Select-Object -ExpandProperty Name
        foreach ($evt in $DdlEvent) {
            $match = $validEvents | Where-Object { $_ -eq $evt } | Select-Object -First 1
            if (-not $match) {
                Stop-Function -Message "Unknown DDL event `"$evt`". Valid events are members of DatabaseDdlTriggerEventSet (for example CreateTable, AlterTable, DropTable, DdlDatabaseLevelEventsEvents)." -Target $evt -FunctionName Set-DbaDbTrigger
                return
            }
            $resolvedEvents += $match
        }
    }

    $triggersToProcess = New-Object System.Collections.Generic.List[object]

    if ($__boundInputObject) {
        foreach ($piped in $InputObject) { $triggersToProcess.Add($piped) }
    }

    if ($__boundSqlInstance) {
        foreach ($instance in $SqlInstance) {
            try {
                $found = Get-DbaDbTrigger -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbTrigger
                continue
            }
            if ($__boundName) {
                $found = $found | Where-Object { $_.Name -in $Name }
            }
            foreach ($f in $found) { $triggersToProcess.Add($f) }
        }
    }

    foreach ($currentTrigger in $triggersToProcess) {
        $db = $currentTrigger.Parent
        $server = $db.Parent

        if ($currentTrigger.IsSystemObject) {
            Stop-Function -Message "DDL trigger $($currentTrigger.Name) in database $($db.Name) is a system object and will not be altered." -Target $currentTrigger -Continue -FunctionName Set-DbaDbTrigger
            continue
        }

        $bodyChange = $__boundDefinition -or $__boundDdlEvent
        if ($bodyChange -and $currentTrigger.ImplementationType -eq [Microsoft.SqlServer.Management.Smo.ImplementationType]::SqlClr) {
            Stop-Function -Message "DDL trigger $($currentTrigger.Name) in database $($db.Name) is a CLR trigger and has no editable text body. Use Invoke-DbaQuery to redeploy the assembly." -Target $currentTrigger -Continue -FunctionName Set-DbaDbTrigger
            continue
        }

        $emit = $false

        if ($bodyChange) {
            if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Altering DDL trigger $($currentTrigger.Name) in database $($db.Name)")) {
                try {
                    $currentTrigger.TextMode = $false
                    if ($__boundDdlEvent) {
                        $eventSet = New-Object Microsoft.SqlServer.Management.Smo.DatabaseDdlTriggerEventSet
                        foreach ($n in $resolvedEvents) { $eventSet.$n = $true }
                        $currentTrigger.DdlTriggerEvents = $eventSet
                    }
                    if ($__boundDefinition) {
                        $currentTrigger.TextBody = $Definition
                    }
                    $currentTrigger.Alter()
                    $emit = $true
                } catch {
                    Stop-Function -Message "Failed to alter DDL trigger $($currentTrigger.Name) in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $currentTrigger -Continue -FunctionName Set-DbaDbTrigger
                    continue
                }
            }
        }

        if ($__boundIsEnabled) {
            if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Setting enabled state of DDL trigger $($currentTrigger.Name) in database $($db.Name)")) {
                try {
                    $currentTrigger.IsEnabled = [bool]$IsEnabled
                    $currentTrigger.Alter()
                    $emit = $true
                } catch {
                    Stop-Function -Message "Failed to set enabled state of DDL trigger $($currentTrigger.Name) in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $currentTrigger -Continue -FunctionName Set-DbaDbTrigger
                    continue
                }
            }
        }

        if ($emit) {
            $currentTrigger.Refresh()
            Get-DbaDbTrigger -SqlInstance $server -Database $db.Name | Where-Object { $_.Name -eq $currentTrigger.Name }
        }
    }
} $SqlInstance $SqlCredential $Database $Name $Definition $DdlEvent $IsEnabled $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundName $__boundDefinition $__boundDdlEvent $__boundIsEnabled @__commonParameters 3>&1 2>&1
""";
}
