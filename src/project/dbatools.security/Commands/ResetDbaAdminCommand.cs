#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Recovers administrative access to a SQL Server instance by restarting it in single-user mode and
/// resetting or creating a sysadmin login.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the service stop/start
/// choreography (including the clustered-vs-standalone split and every rollback path), the single-user-mode
/// net start, the nested SQL executions, the ShouldProcess gates, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// SqlInstance is a MANDATORY SINGULAR parameter and nothing binds from the pipeline, so the command runs
/// exactly one ProcessRecord and the whole function - begin (the two nested helper functions, the -Force
/// ConfirmPreference fold, and the SqlCredential extraction), process, and end - is concatenated into ONE
/// hop scope. The process body is dot-sourced inside that scope so its early return statements (the
/// service-failure rollback paths) exit only the process portion and the end block's completion message still
/// runs, exactly like the function world's block semantics. The nested helpers ConvertTo-PlainText and
/// Invoke-ResetSqlCmd are re-declared verbatim; the Stop-Function inside Invoke-ResetSqlCmd carries NO
/// -FunctionName (the helper's own frame exists in both worlds - stamping it would manufacture the W2-014
/// over-attribution divergence).
/// </para>
/// <para>
/// The SecureString password rides live end to end: it is flattened by the source's own ConvertTo-PlainText
/// only inside interpolated CREATE/ALTER LOGIN statements that sit under ShouldProcess gates, so -WhatIf
/// never materializes a plaintext password, and no Write-Message ever includes it. The interactive Read-Host
/// password prompt for a passwordless SQL login rides verbatim (the W2-199 accepted-deviation class). The
/// command streams through InvokeScopedStreaming because it emits the resulting login object inside a gate
/// and later statements can still Stop-Function under -EnableException (DEF-001). The nine lowercase
/// $pscmdlet.ShouldProcess gates route to $__realCmdlet; ConfirmImpact is High, and -Force suppresses
/// confirmation via the hop-scope ConfirmPreference fold (the proven Copy-family technique). The interpolated
/// T-SQL (CREATE/ALTER LOGIN, xp_instance_regwrite, sp_addsrvrolemember) is source-preserved, not hardened -
/// BP-101 governs C#-authored SQL only.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Reset, "DbaAdmin", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class ResetDbaAdminCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Credential whose username and password seed the login reset.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The login to create or reset. Defaults to sa.</summary>
    [Parameter(Position = 2)]
    public string? Login { get; set; } = "sa";

    /// <summary>New password for the login.</summary>
    [Parameter(Position = 3)]
    public System.Security.SecureString? SecurePassword { get; set; }

    /// <summary>Skips the confirmation prompts before restarting the instance.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Runs the whole begin/process/end flow in one hop for the single bound instance.</summary>
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
            SqlInstance, SqlCredential, Login, SecurePassword, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: begin + dot-sourced process + end, verbatim, in one scope. Substitutions only: $pscmdlet ->
    // $__realCmdlet (the nine ShouldProcess gates); -FunctionName on the 11 DIRECT Stop-Function calls (NOT
    // the one inside the re-declared Invoke-ResetSqlCmd helper); -FunctionName + -ModuleName "dbatools" on
    // the 14 DIRECT Write-Message calls. EnableException and Force received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Login, $SecurePassword, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string]$Login, [System.Security.SecureString]$SecurePassword, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        #region Utility functions
        function ConvertTo-PlainText {
            <#
                .SYNOPSIS
                Internal function.
            #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [Security.SecureString]$Password
            )
            $marshal = [Runtime.InteropServices.Marshal]
            $plaintext = $marshal::PtrToStringAuto($marshal::SecureStringToBSTR($Password))
            return $plaintext
        }

        function Invoke-ResetSqlCmd {
            <#
                .SYNOPSIS
                Internal function. Executes a SQL statement against specified computer, and uses "Reset-DbaAdmin" as the Application Name.
            #>
            [OutputType([System.Boolean])]
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [Alias("ServerInstance", "SqlServer")]
                [DbaInstanceParameter]$instance,
                [string]$sql,
                [switch]$EnableException
            )
            try {
                $connstring = "Data Source=$instance;Integrated Security=True;TrustServerCertificate=true;Connect Timeout=20;Application Name=Reset-DbaAdmin"
                $conn = New-Object Microsoft.Data.SqlClient.SqlConnection $connstring
                $conn.Open()
                $cmd = New-Object Microsoft.Data.sqlclient.sqlcommand($null, $conn)
                $cmd.CommandText = $sql
                $null = $cmd.ExecuteNonQuery()
                $true
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -EnableException $EnableException
                $false
            } finally {
                $cmd.Dispose()
                $conn.Close()
                $conn.Dispose()
            }
        }
        #endregion Utility functions
        if ($Force) { $ConfirmPreference = 'none' }

        if ($SqlCredential) {
            $Login = $SqlCredential.UserName
            $SecurePassword = $SqlCredential.Password
        }
        # Named-wrapper shim: the body runs inside a function carrying the command's name so that
        # call-stack-deriving helpers see Reset-DbaAdmin as they do in the function world.
        # Write-ProgressHelper builds BOTH its Activity string and its TotalSteps lookup from
        # (Get-PSCallStack)[1].Command; from an anonymous scriptblock frame that reads '<ScriptBlock>',
        # so all NINE calls here - none of which pass -Activity or -TotalSteps - emitted
        # 'Executing <ScriptBlock>' at a flat 0%. Dot-sourced, so the body stays in the hop scope.
        function Reset-DbaAdmin {
        foreach ($instance in $SqlInstance) {
            $stepcounter = 0
            $baseaddress = $instance.ComputerName
            # Get hostname

            if ($instance.IsLocalHost) {
                $ipaddr = "."
                $hostName = $env:COMPUTERNAME
                $baseaddress = $env:COMPUTERNAME
            } else {
                $resolved = Resolve-DbaNetworkName -ComputerName $baseaddress
                $ipaddr = $resolved.IPAddress
                $hostName = $resolved.FullComputerName
            }

            # Setup remote session if server is not local
            if (-not $instance.IsLocalHost) {
                try {
                    $connectionParams = @{
                        ComputerName = $hostName
                        ErrorAction  = "Stop"
                        UseSSL       = (Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.UseSSL' -Fallback $false)
                    }

                    [nullable[int]]$Port = Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.Port' -Fallback $null
                    if (($null -ne $Port) -and ($Port -gt 0)) {
                        $connectionParams += @{ Port = $Port }
                    }

                    $session = New-PSSession @connectionParams
                } catch {
                    Stop-Function -Continue -ErrorRecord $_ -Message "Can't access $hostName using PSSession. Check your firewall settings and ensure Remoting is enabled or run the script locally." -FunctionName Reset-DbaAdmin
                }
            }

            Write-Message -Level Verbose -Message "Detecting login type." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
            # Is login a Windows login? If so, does it exist?
            if ($Login -match "\\") {
                Write-Message -Level Verbose -Message "Windows login detected. Checking to ensure account is valid." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                $windowslogin = $true
                try {
                    if ($hostName -eq $env:COMPUTERNAME) {
                        $account = New-Object System.Security.Principal.NTAccount($Login)
                        #Variable $sid marked as unused by PSScriptAnalyzer replace with $null to catch output
                        $null = $account.Translate([System.Security.Principal.SecurityIdentifier])
                    } else {
                        Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $Login -ScriptBlock {
                            $account = New-Object System.Security.Principal.NTAccount($args)
                            #Variable $sid marked as unused by PSScriptAnalyzer replace with $null to catch output
                            $null = $account.Translate([System.Security.Principal.SecurityIdentifier])
                        }
                    }
                } catch {
                    Write-Message -Level Warning -Message "Cannot resolve Windows User or Group $Login. Trying anyway." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                }
            }

            # If it's not a Windows login, it's a SQL login, so it needs a password.
            if (-not $windowslogin -and -not $SecurePassword) {
                Write-Message -Level Verbose -Message "SQL login detected" -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                do {
                    $password = Read-Host -AsSecureString "Please enter a new password for $Login"
                } while ($password.Length -eq 0)
            }

            If ($SecurePassword) {
                $password = $SecurePassword
            }

            # Get instance and service display name, then get services
            $instanceName = $instance.InstanceName
            if (-not $instanceName) {
                $instanceName = "MSSQLSERVER"
            }
            $displayName = "SQL Server ($instanceName)"

            try {
                if ($hostName -eq $env:COMPUTERNAME) {
                    $instanceServices = Get-Service -ErrorAction Stop | Where-Object { $_.DisplayName -like "*($instanceName)*" -and $_.Status -eq "Running" }
                    $sqlservice = Get-Service -ErrorAction Stop | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
                } else {
                    $instanceServices = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object { $_.DisplayName -like "*($instanceName)*" -and $_.Status -eq "Running" }
                    $sqlservice = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
                }
            } catch {
                Stop-Function -Message "Cannot connect to WMI on $hostName or SQL Service does not exist. Check permissions, firewall and SQL Server running status." -ErrorRecord $_ -Target $instance -FunctionName Reset-DbaAdmin
                return
            }

            if (-not $instanceServices) {
                Stop-Function -Message "Couldn't find SQL Server instance. Check the spelling, ensure the service is running and try again." -Target $instance -FunctionName Reset-DbaAdmin
                return
            }

            Write-Message -Level Verbose -Message "Attempting to stop SQL Services." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"

            # Check to see if service is clustered. Clusters don't support -m (since the cluster service
            # itself connects immediately) or -f, so they are handled differently.
            try {
                $checkcluster = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object { $_.Name -eq "ClusSvc" -and $_.Status -eq "Running" }
            } catch {
                Stop-Function -Message "Can't check services." -Target $instance -ErrorRecord $_ -FunctionName Reset-DbaAdmin
                return
            }

            if ($null -ne $checkcluster) {
                $clusterResource = Get-DbaCmObject -ClassName "MSCluster_Resource" -Namespace "root\mscluster" -ComputerName $hostName | Where-Object { $_.Name.StartsWith("SQL Server") -and $_.OwnerGroup -eq "SQL Server ($instanceName)" }
            }

            if ($__realCmdlet.ShouldProcess($baseaddress, "Stop $instance to restart in single-user mode")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Stopping $instance to restart in single-user mode"
                # Take SQL Server offline so that it can be started in single-user mode
                if ($clusterResource.count -gt 0) {
                    $isClustered = $true
                    try {
                        $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.TakeOffline(60) }
                    } catch {
                        $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_ -Target $instance -FunctionName Reset-DbaAdmin
                        return
                    }
                } else {
                    try {
                        Stop-Service -InputObject $sqlservice -Force -ErrorAction Stop
                        Write-Message -Level Verbose -Message "Successfully stopped SQL service." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                    } catch {
                        Start-Service -InputObject $instanceServices -ErrorAction Stop
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL service and quit." -ErrorRecord $_ -Target $instance -FunctionName Reset-DbaAdmin
                        return
                    }
                }
            }

            # /mReset-DbaAdmin Starts an instance of SQL Server in single-user mode and only allows this script to connect.
            if ($__realCmdlet.ShouldProcess($baseaddress, "Starting $instance in single-user mode")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Starting $instance in single-user mode"
                try {
                    if ($instance.IsLocalHost) {
                        $netstart = net start ""$displayName"" /mReset-DbaAdmin 2>&1
                        if ("$netstart" -notmatch "success") {
                            Stop-Function -Message "Restart failure" -Continue -FunctionName Reset-DbaAdmin
                        }
                    } else {
                        $netstart = Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $displayName -ScriptBlock { net start ""$args"" /mReset-DbaAdmin } 2>&1
                        foreach ($line in $netstart) {
                            if ($line.length -gt 0) {
                                Write-Message -Level Verbose -Message $line -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                            }
                        }
                    }
                } catch {
                    Stop-Service -InputObject $sqlservice -Force -ErrorAction SilentlyContinue
                    if ($isClustered) {
                        $clusterResource | Where-Object Name -EQ "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object Name -NE "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                    } else {
                        Start-Service -InputObject $instanceServices -ErrorAction SilentlyContinue
                    }
                    Stop-Function -Message "Couldn't execute net start command. Restarted services and quit." -ErrorRecord $_ -FunctionName Reset-DbaAdmin
                    return
                }
            }

            if ($__realCmdlet.ShouldProcess($baseaddress, "Testing $instance to ensure it's back up")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Testing $instance to ensure it's back up"
                try {
                    $null = Invoke-ResetSqlCmd -instance $instance -Sql "SELECT 1" -EnableException
                } catch {
                    try {
                        Start-Sleep 3
                        $null = Invoke-ResetSqlCmd -instance $instance -Sql "SELECT 1" -EnableException
                    } catch {
                        Stop-Service -InputObject $sqlservice -Force -ErrorAction SilentlyContinue
                        if ($isClustered) {
                            $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                            $clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        } else {
                            Start-Service -InputObject $instanceServices -ErrorAction SilentlyContinue
                        }
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_ -FunctionName Reset-DbaAdmin
                    }
                }
            }

            # Get login. If it doesn't exist, create it.
            if ($__realCmdlet.ShouldProcess($instance, "Adding login $Login if it doesn't exist")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding login $Login if it doesn't exist"
                if ($windowslogin) {
                    $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$Login')
                    BEGIN CREATE LOGIN [$Login] FROM WINDOWS END"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't create Windows login." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                    }

                } elseif ($Login -ne "sa") {
                    # Create new sql user
                $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$Login')
                    BEGIN CREATE LOGIN [$Login] WITH PASSWORD = '$(ConvertTo-PlainText $password)', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF END"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't create SQL login." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                    }
                }
            }

            # If $Login is a SQL Login, Mixed mode authentication is required.
            if ($windowslogin -ne $true) {
                if ($__realCmdlet.ShouldProcess($instance, "Enabling mixed mode authentication for $Login and ensuring account is unlocked")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Enabling mixed mode authentication for $Login and ensuring account is unlocked"
                    $sql = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't set to Mixed Mode." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                    }

                    $sql = "ALTER LOGIN [$Login] WITH CHECK_POLICY = OFF
                    ALTER LOGIN [$Login] WITH PASSWORD = '$(ConvertTo-PlainText $password)' UNLOCK"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't unlock account." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($instance, "Enabling $Login")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensuring login is enabled"
                $sql = "ALTER LOGIN [$Login] ENABLE"
                if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                    Write-Message -Level Warning -Message "Couldn't enable login." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                }
            }

            if ($Login -ne "sa") {
                if ($__realCmdlet.ShouldProcess($instance, "Ensuring $Login exists within sysadmin role")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensuring $Login exists within sysadmin role"
                    $sql = "EXEC sp_addsrvrolemember '$Login', 'sysadmin'"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't add to sysadmin role." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($instance, "Finished with login tasks. Restarting")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Finished with login tasks. Restarting."
                try {
                    Stop-Service -InputObject $sqlservice -Force -ErrorAction Stop
                    if ($isClustered -eq $true) {
                        $clusterResource | Where-Object Name -EQ "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object Name -NE "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                    } else {
                        Start-Service -InputObject $instanceServices -ErrorAction Stop
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Reset-DbaAdmin
                }
            }

            if ($__realCmdlet.ShouldProcess($instance, "Logging in to get account information")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Logging in to get account information"
                if ($SecurePassword) {
                    $cred = New-Object System.Management.Automation.PSCredential ($Login, $SecurePassword)
                    Get-DbaLogin -SqlInstance $instance -SqlCredential $cred -Login $Login
                } elseif ($SqlCredential) {
                    Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login
                } else {
                    try {
                        Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login -EnableException
                    } catch {
                        Stop-Function -Message "Password not supplied, tried logging in with Integrated authentication and it failed. Either way, $Login should work now on $instance." -Continue -FunctionName Reset-DbaAdmin
                    }
                }
            }

        }
        }
        . Reset-DbaAdmin
        Write-Message -Level Verbose -Message "Script complete." -FunctionName Reset-DbaAdmin -ModuleName "dbatools"
} $SqlInstance $SqlCredential $Login $SecurePassword $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
