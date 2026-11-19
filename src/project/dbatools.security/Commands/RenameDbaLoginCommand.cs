#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Renames a SQL Server login, optionally renaming its mapped database users when -Force is supplied.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the login rename, the optional
/// database-user renames and rollback, the ShouldProcess gate, the output shape, and dbatools stream and error
/// handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, and it streams its output through InvokeScopedStreaming: the body
/// emits the login-rename result and, under -Force, one object per renamed database user, and its -Force
/// rollback path emits a status object and then Stop-Function-terminates under -EnableException - a buffered
/// call would drop that already-emitted output before the throw, so streaming is required. SqlInstance is a
/// plain (non-pipeline) Mandatory parameter, so there is no pipeline input and no cross-record state. The
/// callback dispatches ErrorRecords to WriteError, else WriteObject. EnableException and Force are carried as
/// plain (untyped) values, because a switch in the inner CmdletBinding scriptblock is excluded from positional
/// binding. The six DIRECT Stop-Function/Write-Message calls take -FunctionName; $Pscmdlet is redirected to the
/// real cmdlet ($__realCmdlet) for the two ShouldProcess gates. The SMO Rename() calls are left unedited.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Rename, "DbaLogin", DefaultParameterSetName = "Default", SupportsShouldProcess = true)]
public sealed class RenameDbaLoginCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The current login name to rename.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [PsStringCast]
    public string? Login { get; set; }

    /// <summary>The new login name.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [PsStringCast]
    public string? NewLogin { get; set; }

    /// <summary>Also renames the mapped database users, rolling back the login rename if any user rename fails.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Renames the login for the bound instances.</summary>
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
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Login, NewLogin, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet (the two ShouldProcess gates);
    // -FunctionName on the six DIRECT Stop-Function/Write-Message calls. EnableException and Force received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Login, $NewLogin, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string]$Login, [string]$NewLogin, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Rename-DbaLogin
            }

            $databases = $server.Databases | Where-Object IsAccessible
            $currentLogin = $server.Logins[$Login]

            if ( -not $currentLogin) {
                Stop-Function -Message "Login '$login' not found on $instance" -Target login -Continue -FunctionName Rename-DbaLogin
            }

            if ($__realCmdlet.ShouldProcess($SqlInstance, "Changing Login name from  [$Login] to [$NewLogin]")) {
                $output = @()
                try {
                    $dbMappings = $currentLogin.EnumDatabaseMappings()
                    $null = $currentLogin.Rename($NewLogin)
                    $output += [PSCustomObject]@{
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.ServiceName
                        SqlInstance   = $server.DomainInstanceName
                        Database      = $null
                        PreviousLogin = $Login
                        NewLogin      = $NewLogin
                        PreviousUser  = $null
                        NewUser       = $null
                        Status        = "Successful"
                    }
                } catch {
                    $dbMappings = $null
                    [PSCustomObject]@{
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.ServiceName
                        SqlInstance   = $server.DomainInstanceName
                        Database      = $null
                        PreviousLogin = $Login
                        NewLogin      = $NewLogin
                        PreviousUser  = $null
                        NewUser       = $null
                        Status        = "Failure"
                    }
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $login -Continue -FunctionName Rename-DbaLogin
                }
            }

            if ($Force) {
                foreach ($mapping in $dbMappings) {
                    $db = $databases | Where-Object Name -eq $mapping.DBName
                    $user = $db.Users[$Login]
                    if ($user) {
                        Write-Message -Level Verbose -Message "Starting update for $db" -FunctionName Rename-DbaLogin -ModuleName "dbatools"

                        if ($__realCmdlet.ShouldProcess($SqlInstance, "Changing database $db user $user from [$Login] to [$NewLogin]")) {
                            try {
                                $oldname = $user.name
                                $null = $user.Rename($NewLogin)
                                $output += [PSCustomObject]@{
                                    ComputerName  = $server.ComputerName
                                    InstanceName  = $server.ServiceName
                                    SqlInstance   = $server.DomainInstanceName
                                    Database      = $db.name
                                    PreviousLogin = $null
                                    NewLogin      = $null
                                    PreviousUser  = $oldname
                                    NewUser       = $NewLogin
                                    Status        = "Successful"
                                }
                            } catch {
                                Write-Message -Level Warning -Message "Rolling back update to login: $Login" -FunctionName Rename-DbaLogin -ModuleName "dbatools"
                                $null = $currentLogin.Rename($Login)

                                [PSCustomObject]@{
                                    ComputerName  = $server.ComputerName
                                    InstanceName  = $server.ServiceName
                                    SqlInstance   = $server.DomainInstanceName
                                    Database      = $db.name
                                    PreviousLogin = $null
                                    NewLogin      = $null
                                    PreviousUser  = $NewLogin
                                    NewUser       = $oldname
                                    Status        = "Failure to rename. Rolled back change."
                                }
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $NewLogin -FunctionName Rename-DbaLogin
                                return
                            }
                        }
                    }
                }
            }

            $output
        }
} $SqlInstance $SqlCredential $Login $NewLogin $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
