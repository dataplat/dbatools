#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates server-level roles on one or more SQL Server instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the connection handling, the
/// duplicate-role guard, the SMO role creation, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// This row needs NO state sentinel, which was established by classifying every local the process block
/// mutates rather than by assuming. $server and $serverRoles are re-assigned at the top of each instance
/// iteration before anything reads them. $newServerRole is assigned inside the try, but unlike the sibling
/// New-Dba* rows in this satellite its catch calls Stop-Function WITHOUT -Target, so no stale value from a
/// previous record can be observed - the cross-record carry those rows needed does not arise here.
/// </para>
/// <para>
/// The command streams through InvokeScopedStreaming: it emits per role created and a later role can raise
/// a terminating -EnableException failure, so a buffered call would discard the roles already created and
/// reported (DEF-001). The empty-ServerRole guard calls Stop-Function with no -Continue followed by return,
/// which ends that RECORD only - it sets no interrupt latch the script would carry forward, so no DEF-011
/// latch is needed.
/// </para>
/// <para>
/// The ShouldProcess call uses the SINGLE-argument overload, passing the whole sentence as the target. That
/// reads oddly against the two-argument form the sibling rows use, but it is what the source does and it
/// changes the -WhatIf and -Confirm text, so it is carried verbatim.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaServerRole", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class NewDbaServerRoleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The server-level roles to create.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? ServerRole { get; set; }

    /// <summary>The login that owns the new roles.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Owner { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Creates the server-level roles on the instances bound to the current record.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, ServerRole, Owner, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet (the ShouldProcess
    // gate, single-argument overload preserved); -FunctionName on the 4 DIRECT Stop-Function calls and
    // -FunctionName + -ModuleName "dbatools" on the 1 DIRECT Write-Message call. There are no Test-Bound
    // calls in this body and no cross-record state, so no sentinel is emitted.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $ServerRole, $Owner, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [String[]]$ServerRole, [String]$Owner, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (-not $ServerRole) {
            Stop-Function -Message "You must specify a new server-level role name. Use -ServerRole parameter." -FunctionName New-DbaServerRole
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaServerRole
            }

            $serverRoles = $server.Roles

            foreach ($role in $ServerRole) {
                if ($serverRoles | Where-Object Name -eq $role) {
                    Stop-Function -Message "The server-level role $role already exists on instance $server." -Target $instance -Continue -FunctionName New-DbaServerRole
                }

                if ($__realCmdlet.ShouldProcess("Creating new server-level role $role on $server")) {
                    Write-Message -Level Verbose -Message "Creating new server-level role $role on $server" -FunctionName New-DbaServerRole -ModuleName "dbatools"
                    try {
                        $newServerRole = New-Object -TypeName Microsoft.SqlServer.Management.Smo.ServerRole
                        $newServerRole.Name = $role
                        $newServerRole.Parent = $server

                        if ($Owner) {
                            $newServerRole.Owner = $Owner
                        }

                        $newServerRole.Create()

                        Get-DbaServerRole -SqlInstance $server -ServerRole $role -EnableException
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName New-DbaServerRole
                    }
                }
            }
        }
} $SqlInstance $SqlCredential $ServerRole $Owner $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
