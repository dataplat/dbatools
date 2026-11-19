#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes members from database roles. Port of public/Remove-DbaDbRoleMember.ps1; the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// Process-only: the source has no begin or end block, so the hop is a single per-record
/// invocation. No local needs a cross-record carry - $input, $inputType, $dbRoles, $dbRole,
/// $db and $instance are each assigned and read inside one loop iteration, and $InputObject is
/// re-bound from the pipeline on every record before the body re-points it at $SqlInstance.
///
/// No graceful-stop latch: the source has no Test-FunctionInterrupt guard, so a later record
/// re-enters the process body and re-evaluates its input guard, warning again. Carrying a latch
/// would suppress warnings the function repeats.
///
/// ONE Test-Bound call site is substituted: Test-Bound -Not -ParameterName Role becomes the carried
/// $__boundRole flag, computed as MyInvocation.BoundParameters.ContainsKey(Role) rather than from the
/// parameter truthiness, because Test-Bound reports BOUNDNESS - an explicit -Role $null is bound but
/// falsy, and reading truthiness would disagree with the function on exactly those calls. The carrier
/// is declared in BOTH param blocks and passed by the trailing invocation. An earlier revision
/// referenced it WITHOUT wiring it, so it was $null on every call and the guard behaved as though
/// -Role were never supplied, rejecting input the function accepts; Test-CarrierWiring.ps1 now fails
/// the build on that shape.
///
/// The ShouldProcess gate is routed to the OUTER cmdlet. ConfirmImpact is High, so this command
/// prompts by default and -Confirm's "Yes to All" answer - which lives on the invoking runtime -
/// must survive between records rather than being forgotten by a per-record inner runtime.
///
/// Two source shapes ship unchanged because parity is the contract. The element loop variable is
/// $input, shadowing the PowerShell automatic; that was probed across the function,
/// module-scriptblock and production-hop shapes and behaves identically in all three, so it needs
/// no shim. And the default branch of the input-type switch does Stop-Function then a bare return,
/// which abandons the whole record rather than just that element.
///
/// The hop streams rather than buffers. This command removes role members and each emitted object records
/// one that was actually removed, so a buffered invocation would discard the audit trail of
/// completed removals if a later role threw under -EnableException.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbRoleMember", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaDbRoleMemberCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only these databases.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>Only these roles.</summary>
    [Parameter(Position = 3)]
    public string[]? Role { get; set; }

    /// <summary>The user or users to remove from the role.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    public string[]? User { get; set; }

    /// <summary>Server, database or role objects.</summary>
    [Parameter(Position = 5, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

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
        }, BodyScript,
            SqlInstance, SqlCredential, Database, Role, User, InputObject, EnableException.ToBool(), this,
            MyInvocation.BoundParameters.ContainsKey("Role"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's process body VERBATIM. Substitutions only: $PSCmdlet -> $__realCmdlet so the
    // gate is owned by the outer cmdlet, and -FunctionName on Stop-Function/Write-Message. The body
    // is embedded WITHOUT added indentation, since indenting rewrites multi-line string literals.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Role, $User, $InputObject, $EnableException, $__realCmdlet, $__boundRole, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Role, [string[]]$User, [object[]]$InputObject, $EnableException, $__realCmdlet, $__boundRole, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a role, database, or server or specify a SqlInstance" -FunctionName Remove-DbaDbRoleMember
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Remove-DbaDbRoleMember -ModuleName "dbatools"
                    $dbRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -Role $Role
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Remove-DbaDbRoleMember -ModuleName "dbatools"
                    $dbRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -Role $Role
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject" -FunctionName Remove-DbaDbRoleMember -ModuleName "dbatools"
                    $dbRoles = $input | Get-DbaDbRole -Role $Role
                }
                'Microsoft.SqlServer.Management.Smo.DatabaseRole' {
                    Write-Message -Level Verbose -Message "Processing DatabaseRole through InputObject" -FunctionName Remove-DbaDbRoleMember -ModuleName "dbatools"
                    $dbRoles = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or database role." -FunctionName Remove-DbaDbRoleMember
                    return
                }
            }

            if ((-not $__boundRole) -and ($inputType -ne 'Microsoft.SqlServer.Management.Smo.DatabaseRole')) {
                Stop-Function -Message "You must pipe in a DatabaseRole or specify a Role." -FunctionName Remove-DbaDbRoleMember
                return
            }

            foreach ($dbRole in $dbRoles) {
                $db = $dbRole.Parent
                $instance = $db.Parent

                Write-Message -Level 'Verbose' -Message "Getting Database Role Members for $dbRole in $db on $instance" -FunctionName Remove-DbaDbRoleMember -ModuleName "dbatools"

                $members = $dbRole.EnumMembers()

                foreach ($username in $User) {
                    if ($members -contains $username) {
                        if ($__realCmdlet.ShouldProcess($instance, "Removing User $username from role: $dbRole in database $db")) {
                            Write-Message -Level 'Verbose' -Message "Removing User $username from role: $dbRole in database $db on $instance" -FunctionName Remove-DbaDbRoleMember -ModuleName "dbatools"
                            $dbRole.DropMember($username)
                        }
                    }
                }
            }
        }

} $SqlInstance $SqlCredential $Database $Role $User $InputObject $EnableException $__realCmdlet $__boundRole $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
