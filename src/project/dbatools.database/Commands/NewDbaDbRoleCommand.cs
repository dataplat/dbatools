#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates one or more database roles. Port of public/New-DbaDbRole.ps1; the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// PROCESS-ONLY, one hop. $InputObject is ValueFromPipeline, so process fires per piped database.
///
/// NO INTERRUPT BRIDGE, deliberately - the same ruling as W2-144. The two guards at :104-112 ("You
/// must pipe in a database or specify a SqlInstance", "You must specify a new role name") are
/// Stop-Function WITHOUT -Continue, so they DO set the module latch, but this source contains NO
/// Test-FunctionInterrupt anywhere to read it back. The guards therefore re-evaluate and warn on
/// EVERY record, and bridging the latch would emit ONE warning where the source emits N. The rule:
/// bridge only where the SOURCE reads the latch back. Contrast W2-145, which does read it at :249
/// and therefore does bridge. Mechanism measured in migration/logs/probe-20260718-latch-sentinel.
///
/// NO CROSS-RECORD CARRY. Source :116 does "$InputObject += Get-DbaDatabase ..." and :120 reassigns
/// "$InputObject = $InputObject | Where-Object ...", but both target the PIPELINE-BOUND PARAMETER,
/// which the binder rewrites before every record, so neither mutation can outlive its record. That
/// is the cheap branch of the carry question - contrast New-DbaDacProfile (W2-142) and
/// New-DbaDbMaskingConfig (W2-145), where the same "+=" shape targeted plain locals and DID carry.
/// Verified mechanically as well as by reading: migration/tools/Find-AccumulatorCarry.ps1 reports
/// zero accumulator candidates for this source. Every other local ($server :123, $dbRoles :126,
/// $newRole :137, and the loop variables $db and $r) is assigned before use within its own
/// iteration.
///
/// NO Test-Bound SITES AT ALL, so this row carries no caller-boundness flags - the first row in my
/// range where that is true.
///
/// A SOURCE QUIRK RIDES VERBATIM: the ShouldProcess message at :135 interpolates $role - the whole
/// requested ARRAY - rather than $r, the role actually being created, so the confirmation prompt
/// names every requested role on each iteration. Preserved, not corrected; recorded here so no
/// reviewer reads it as port drift.
///
/// STREAMING, NOT BUFFERED (DEF-001): roles are created one at a time and each is emitted via
/// Select-DefaultView, so a buffered hop would discard the record of roles already created when a
/// later failure terminated the hop under -EnableException.
///
/// The one $Pscmdlet.ShouldProcess gate at :135 routes to the real cmdlet via $__realCmdlet - which
/// matters at ConfirmImpact Medium, where the prompt is reachable at the default $ConfirmPreference.
/// The two in-loop Stop-Function calls (:130 role exists, :156 create failure) carry -Continue.
/// EnableException crosses as a SwitchParameter OBJECT received untyped, per B's combined rule
/// (a typed [switch] hop param shifts positional binding; .ToBool() silently breaks .IsPresent).
/// In-hop Stop-Function/Write-Message calls carry -FunctionName. Implicit positions 0-6 are made
/// explicit per the W2-071 law and were confirmed against the exported baseline rather than assumed.
/// Surface pinned by migration/baselines/New-DbaDbRole.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbRole", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class NewDbaDbRoleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the role is created in.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Databases to exclude.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The name(s) of the role(s) to create.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Role { get; set; }

    /// <summary>The role owner; defaults to dbo when not supplied.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? Owner { get; set; }

    /// <summary>Databases piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {

        // Streaming, not buffered (DEF-001): roles are created and emitted one at a time, so a
        // buffered hop would drop the audit trail of roles already created.
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Role, Owner, InputObject,
            EnableException, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM, dot-sourced so its two early returns exit only the body and
    // not the whole hop. Edits: the one $Pscmdlet gate routes to $__realCmdlet, and -FunctionName is
    // stamped on the six Stop-Function/Write-Message calls. NO sentinel epilogue: this source never
    // reads the interrupt latch back (no Test-FunctionInterrupt), so its guards must re-warn per
    // record exactly as they do here.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Role, $Owner, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [String[]]$Role, [String]$Owner, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance." -FunctionName New-DbaDbRole
            return
        }

        if (-not $Role) {
            Stop-Function -Message "You must specify a new role name." -FunctionName New-DbaDbRole
            return
        }

        if ($SqlInstance) {
            foreach ($instance in $SqlInstance) {
                $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            }
        }

        $InputObject = $InputObject | Where-Object { $_.IsAccessible -eq $true }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            Write-Message -Level 'Verbose' -Message "Getting Database Roles for $db on $server" -FunctionName New-DbaDbRole -ModuleName "dbatools"

            $dbRoles = $db.Roles

            foreach ($r in $Role) {
                if ($dbRoles | Where-Object Name -eq $r) {
                    Stop-Function -Message "The $r role already exist within database $db on instance $server." -Target $db -Continue -FunctionName New-DbaDbRole
                }

                Write-Message -Level Verbose -Message "Add roles to Database $db on target $server" -FunctionName New-DbaDbRole -ModuleName "dbatools"

                if ($__realCmdlet.ShouldProcess("Creating new DatabaseRole $role on database $db", $server)) {
                    try {
                        $newRole = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DatabaseRole
                        $newRole.Name = $r
                        $newRole.Parent = $db

                        if ($Owner) {
                            $newRole.Owner = $Owner
                        } else {
                            $newRole.Owner = "dbo"
                        }

                        $newRole.Create()

                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name ParentName -value $db.Name

                        Select-DefaultView -InputObject $newRole -Property ComputerName, InstanceName, SqlInstance, Name, 'ParentName as Parent', Owner
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName New-DbaDbRole
                    }
                }
            }

        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Role $Owner $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
