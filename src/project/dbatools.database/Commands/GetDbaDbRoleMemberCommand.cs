#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves database role membership from databases, servers, or piped role/database/server objects. Port of
/// public/Get-DbaDbRoleMember.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port with TWO ValueFromPipeline parameters (SqlInstance pos0, InputObject object[] pos6). The
/// process body type-dispatches each InputObject item (DbaInstanceParameter/Server/Database/DatabaseRole) via a
/// switch that delegates to the now-compiled Get-DbaDbRole. TWO bare-return guards: the neither-piped guard
/// (source 137) and the unknown-InputObject-type default branch (source 179); both Stop-Function (no -Continue)
/// + bare return exit the hop scriptblock cleanly - a bare return does NOT propagate out of & $module {} (the
/// bare-return law), reproducing the source's per-record stop. ONE Test-Bound: Test-Bound -Not -ParameterName
/// 'IncludeSystemUser' (193) becomes -not $__boundIncludeSystemUser (carried flag TestBound(nameof(IncludeSystemUser)),
/// keeping the if's own parens). No accumulator, no interrupt, no ShouldProcess. The only other edits are
/// -FunctionName Get-DbaDbRoleMember on the two Stop-Function and five Write-Message. Surface pinned by
/// migration/baselines/Get-DbaDbRoleMember.json (positions 0-6, two non-positional switches, two VFP, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbRoleMember")]
public sealed class GetDbaDbRoleMemberCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Filter to the specified database role(s).</summary>
    [Parameter(Position = 4)]
    public string[]? Role { get; set; }

    /// <summary>The database role(s) to exclude.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeRole { get; set; }

    /// <summary>Exclude the fixed database roles (and public).</summary>
    [Parameter]
    public SwitchParameter ExcludeFixedRole { get; set; }

    /// <summary>Include system users in the membership results.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemUser { get; set; }

    /// <summary>Server, database, or database-role object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
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
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Role, ExcludeRole, ExcludeFixedRole.ToBool(),
            InputObject, EnableException.ToBool(), TestBound(nameof(IncludeSystemUser)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the process block VERBATIM. Edits: -FunctionName Get-DbaDbRoleMember on the two Stop-Function and
    // five Write-Message; Test-Bound -Not -ParameterName 'IncludeSystemUser' -> -not $__boundIncludeSystemUser
    // (carried flag). Both bare returns (neither-piped guard, unknown-type default) exit the scriptblock cleanly.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Role, $ExcludeRole, $ExcludeFixedRole, $InputObject, $EnableException, $__boundIncludeSystemUser, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$Role, [string[]]$ExcludeRole, $ExcludeFixedRole, [object[]]$InputObject, $EnableException, $__boundIncludeSystemUser, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a role, database, or server or specify a SqlInstance" -FunctionName Get-DbaDbRoleMember
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            $dbRoleParams = @{
                SqlInstance      = $input
                SqlCredential    = $SqlCredential
                Database         = $Database
                ExcludeDatabase  = $ExcludeDatabase
                Role             = $Role
                ExcludeRole      = $ExcludeRole
                ExcludeFixedRole = $ExcludeFixedRole
                EnableException  = $EnableException
            }
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Get-DbaDbRoleMember -ModuleName "dbatools"
                    $dbRoles = Get-DbaDbRole @dbRoleParams
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Get-DbaDbRoleMember -ModuleName "dbatools"
                    $dbRoles = Get-DbaDbRole @dbRoleParams
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    $dbRoleParams.Remove('SqlInstance')
                    $dbRoleParams.Remove('SqlCredential')
                    $dbRoleParams.Remove('Database')
                    Write-Message -Level Verbose -Message "Processing Database through InputObject" -FunctionName Get-DbaDbRoleMember -ModuleName "dbatools"
                    $dbRoles = $input | Get-DbaDbRole @dbRoleParams
                }
                'Microsoft.SqlServer.Management.Smo.DatabaseRole' {
                    Write-Message -Level Verbose -Message "Processing DatabaseRole through InputObject" -FunctionName Get-DbaDbRoleMember -ModuleName "dbatools"
                    $dbRoles = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or database role." -FunctionName Get-DbaDbRoleMember
                    return
                }
            }
            foreach ($dbRole in $dbRoles) {
                $db = $dbRole.Parent
                $server = $db.Parent
                Write-Message -Level 'Verbose' -Message "Getting Database Role Members for $dbRole in $db on $server" -FunctionName Get-DbaDbRoleMember -ModuleName "dbatools"

                $members = $dbRole.EnumMembers()
                foreach ($member in $members) {
                    $memberUser = $db.Users | Where-Object { $_.Name -eq $member }
                    $memberRole = $db.Roles | Where-Object { $_.Name -eq $member }

                    if (-not $__boundIncludeSystemUser) {
                        $memberUser = $memberUser | Where-Object { $_.IsSystemObject -eq $false }
                    }

                    if ($memberUser) {
                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $db.Name
                            Role          = $dbRole.Name
                            UserName      = $memberUser.Name
                            Login         = $memberUser.Login
                            MemberRole    = $null
                            SmoRole       = $dbRole
                            SmoUser       = $memberUser
                            SmoMemberRole = $null
                        }
                    } elseif ($memberRole) {
                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $db.Name
                            Role          = $dbRole.Name
                            UserName      = $null
                            Login         = $memberUser.Login
                            MemberRole    = $memberRole.Name
                            SmoRole       = $dbRole
                            SmoUser       = $null
                            SmoMemberRole = $memberRole
                        }
                    }
                }
            }
        }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Role $ExcludeRole $ExcludeFixedRole $InputObject $EnableException $__boundIncludeSystemUser $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
