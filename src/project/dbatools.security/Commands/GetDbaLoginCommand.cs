#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Gets the login accounts on a SQL Server instance, with optional filtering and detailed password properties.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the login enumeration, the
/// filter chain, the last-login and password-property queries, the added note properties, the default view,
/// and dbatools stream and error handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The script's begin block only defines two constant SQL template strings, and its process block never
/// mutates them or carries anything else between records, so those two assignments ride at the top of the
/// per-record hop: recomputing identical literals per record is behaviourally indistinguishable from the
/// script's begin-once, and it avoids a sentinel that would carry no state. The command streams through
/// InvokeScopedStreaming rather than buffering, because SqlInstance is an array: one record can emit logins
/// for an early instance and then hit the connection Stop-Function on a later one, which terminates under
/// -EnableException, and a buffered call would discard the logins already produced (DEF-001).
/// </para>
/// <para>
/// The source gates every filter on plain variable truthiness rather than Test-Bound, so no boundness flags
/// are carried. All switches and EnableException are carried as plain (untyped) values, because a switch in
/// the inner CmdletBinding scriptblock is excluded from positional binding. The only body edits are message
/// attribution: -FunctionName on the single direct Stop-Function call, and -FunctionName plus -ModuleName
/// "dbatools" on the two direct Write-Message calls. The SQL templates, the LOGINPROPERTY placeholder
/// substitution, the SID hex-string build, and the Select-DefaultView list are preserved verbatim.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaLogin")]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.Login))]
public sealed class GetDbaLoginCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The logins to return.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Login { get; set; }

    /// <summary>Wildcard patterns a login name must match to be returned.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? IncludeFilter { get; set; }

    /// <summary>Logins to exclude from the results.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? ExcludeLogin { get; set; }

    /// <summary>Wildcard patterns that exclude matching login names.</summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? ExcludeFilter { get; set; }

    /// <summary>Excludes system logins from the results.</summary>
    [Parameter]
    [Alias("ExcludeSystemLogins")]
    public SwitchParameter ExcludeSystemLogin { get; set; }

    /// <summary>Restricts the results to Windows or SQL logins.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    [ValidateSet("Windows", "SQL")]
    public string? Type { get; set; }

    /// <summary>Returns only logins that have access to the instance.</summary>
    [Parameter]
    public SwitchParameter HasAccess { get; set; }

    /// <summary>Returns only locked logins.</summary>
    [Parameter]
    public SwitchParameter Locked { get; set; }

    /// <summary>Returns only disabled logins.</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>Returns only logins that must change their password at next login.</summary>
    [Parameter]
    public SwitchParameter MustChangePassword { get; set; }

    /// <summary>Adds the password and lockout properties to each login.</summary>
    [Parameter]
    public SwitchParameter Detailed { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Returns the logins for the instances bound to the current record.</summary>
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
            SqlInstance, SqlCredential, Login, IncludeFilter, ExcludeLogin, ExcludeFilter,
            ExcludeSystemLogin.ToBool(), Type, HasAccess.ToBool(), Locked.ToBool(), Disabled.ToBool(),
            MustChangePassword.ToBool(), Detailed.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's two constant SQL templates, then the process body VERBATIM. Substitutions
    // only: -FunctionName on the single DIRECT Stop-Function call; -FunctionName +
    // on the two DIRECT Write-Message calls. The switches and EnableException are received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Login, $IncludeFilter, $ExcludeLogin, $ExcludeFilter, $ExcludeSystemLogin, $Type, $HasAccess, $Locked, $Disabled, $MustChangePassword, $Detailed, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Login, [string[]]$IncludeFilter, [string[]]$ExcludeLogin, [string[]]$ExcludeFilter, $ExcludeSystemLogin, [string]$Type, $HasAccess, $Locked, $Disabled, $MustChangePassword, $Detailed, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        $loginTimeSql = "SELECT login_name, MAX(login_time) AS login_time FROM sys.dm_exec_sessions GROUP BY login_name"
        $loginProperty = "SELECT
                            LOGINPROPERTY ('/*LoginName*/' , 'BadPasswordCount') AS BadPasswordCount ,
                            LOGINPROPERTY ('/*LoginName*/' , 'BadPasswordTime') AS BadPasswordTime,
                            LOGINPROPERTY ('/*LoginName*/' , 'DaysUntilExpiration') AS DaysUntilExpiration,
                            LOGINPROPERTY ('/*LoginName*/' , 'HistoryLength') AS HistoryLength,
                            LOGINPROPERTY ('/*LoginName*/' , 'IsMustChange') AS IsMustChange,
                            LOGINPROPERTY ('/*LoginName*/' , 'LockoutTime') AS LockoutTime,
                            CONVERT (VARCHAR(514),  (LOGINPROPERTY('/*LoginName*/', 'PasswordHash')),1) AS PasswordHash,
                            LOGINPROPERTY ('/*LoginName*/' , 'PasswordLastSetTime') AS PasswordLastSetTime"

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaLogin
            }

            $serverLogins = $server.Logins

            if ($Login) {
                $serverLogins = $serverLogins | Where-Object Name -in $Login
            }

            if ($ExcludeSystemLogin) {
                $serverLogins = $serverLogins | Where-Object IsSystemObject -eq $false
            }

            if ($Type -eq 'Windows') {
                $serverLogins = $serverLogins | Where-Object LoginType -in @('WindowsUser', 'WindowsGroup')
            }

            if ($Type -eq 'SQL') {
                $serverLogins = $serverLogins | Where-Object LoginType -eq 'SqlLogin'
            }

            if ($IncludeFilter) {
                $serverLogins = $serverLogins | Where-Object {
                    foreach ($filter in $IncludeFilter) {
                        if ($_.Name -like $filter) {
                            return $true;
                        }
                    }
                }
            }

            if ($ExcludeLogin) {
                $serverLogins = $serverLogins | Where-Object Name -NotIn $ExcludeLogin
            }

            if ($ExcludeFilter) {
                foreach ($filter in $ExcludeFilter) {
                    $serverLogins = $serverLogins | Where-Object Name -NotLike $filter
                }
            }

            if ($HasAccess) {
                $serverLogins = $serverLogins | Where-Object HasAccess
            }

            if ($Locked) {
                $serverLogins = $serverLogins | Where-Object IsLocked
            }

            if ($Disabled) {
                $serverLogins = $serverLogins | Where-Object IsDisabled
            }

            if ($MustChangePassword) {
                $serverLogins = $serverLogins | Where-Object MustChangePassword
            }

            # There's no reliable method to get last login time with SQL Server 2000, so only show on 2005+
            if ($server.VersionMajor -gt 9) {
                Write-Message -Level Verbose -Message "Getting last login times" -FunctionName Get-DbaLogin -ModuleName "dbatools"
                $loginTimes = $server.ConnectionContext.ExecuteWithResults($loginTimeSql).Tables[0]
            } else {
                $loginTimes = $null
            }

            foreach ($serverLogin in $serverLogins) {
                Write-Message -Level Verbose -Message "Processing $serverLogin on $instance" -FunctionName Get-DbaLogin -ModuleName "dbatools"
                $loginTime = $loginTimes | Where-Object { $_.login_name -eq $serverLogin.name } | Select-Object -ExpandProperty login_time

                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name LastLogin -Value $loginTime

                if ($Detailed) {
                    $loginName = $serverLogin.name
                    $query = $loginProperty.Replace('/*LoginName*/', "$loginName")
                    $loginProperties = $server.ConnectionContext.ExecuteWithResults($query).Tables[0]
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name BadPasswordCount -Value $loginProperties.BadPasswordCount
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name BadPasswordTime -Value $loginProperties.BadPasswordTime
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name DaysUntilExpiration -Value $loginProperties.DaysUntilExpiration
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name HistoryLength -Value $loginProperties.HistoryLength
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name IsMustChange -Value $loginProperties.IsMustChange
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name LockoutTime -Value $loginProperties.LockoutTime
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name PasswordHash -Value $loginProperties.PasswordHash
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name PasswordLastSetTime -Value $loginProperties.PasswordLastSetTime
                }

                $sidString = '0x'
                foreach ($element in $serverLogin.Sid) {
                    $sidString += '{0:X2}' -f $element
                }
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name SidString -Value $sidString

                Select-DefaultView -InputObject $serverLogin -Property ComputerName, InstanceName, SqlInstance, Name, LoginType, CreateDate, LastLogin, HasAccess, IsLocked, IsDisabled, MustChangePassword
            }
        }
} $SqlInstance $SqlCredential $Login $IncludeFilter $ExcludeLogin $ExcludeFilter $ExcludeSystemLogin $Type $HasAccess $Locked $Disabled $MustChangePassword $Detailed $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
