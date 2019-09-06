function Reset-DbaAdmin {
    <#
    .SYNOPSIS
        This function allows administrators to regain access to SQL Servers in the event that passwords or access was lost.

        Supports SQL Server 2005 and above. Windows administrator access is required.

    .DESCRIPTION
        This function allows administrators to regain access to local or remote SQL Servers by either resetting the sa password, adding the sysadmin role to existing login, or adding a new login (SQL or Windows) and granting it sysadmin privileges.

        This is accomplished by stopping the SQL services or SQL Clustered Resource Group, then restarting SQL via the command-line using the /mReset-DbaAdmin parameter which starts the server in Single-User mode and only allows this script to connect.

        Once the service is restarted, the following tasks are performed:
        - Login is added if it doesn't exist
        - If login is a Windows User, an attempt is made to ensure it exists
        - If login is a SQL Login, password policy will be set to OFF when creating the login, and SQL Server authentication will be set to Mixed Mode.
        - Login will be enabled and unlocked
        - Login will be added to sysadmin role

        If failures occur at any point, a best attempt is made to restart the SQL Server.

        In order to make this script as portable as possible, System.Data.SqlClient and Get-WmiObject are used (as opposed to requiring the Failover Cluster Admin tools or SMO).

        If using this function against a remote SQL Server, ensure WinRM is configured and accessible. If this is not possible, run the script locally.

        Tested on Windows XP, 7, 8.1, Server 2012 and Windows Server Technical Preview 2.
        Tested on SQL Server 2005 SP4 through 2016 CTP2.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server must be 2005 and above, and can be a clustered or stand-alone instance.

    .PARAMETER SqlCredential
        Instead of using Login and SecurePassword, you can just pass in a credential object.

    .PARAMETER Login
        By default, the Login parameter is "sa" but any other SQL or Windows account can be specified. If a login does not currently exist, it will be added.

        When adding a Windows login to remote servers, ensure the SQL Server can add the login (ie, don't add WORKSTATION\Admin to remoteserver\instance. Domain users and Groups are valid input.

    .PARAMETER SecurePassword
        By default, if a SQL Login is detected, you will be prompted for a password. Use this to securely bypass the prompt.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Login(s) will be dropped and recreated on Destination. Logins that own Agent jobs cannot be dropped at this time.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WSMan
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: Admin access to server (not SQL Services),
        Remoting must be enabled and accessible if $instance is not local

    .LINK
        https://dbatools.io/Reset-DbaAdmin

    .EXAMPLE
        PS C:\> Reset-DbaAdmin -SqlInstance sqlcluster -SqlCredential sqladmin

        Prompts for password, then resets the "sqladmin" account password on sqlcluster.

    .EXAMPLE
        PS C:\> Reset-DbaAdmin -SqlInstance sqlserver\sqlexpress -Login ad\administrator -Confirm:$false

        Adds the domain account "ad\administrator" as a sysadmin to the SQL instance.

        If the account already exists, it will be added to the sysadmin role.

        Does not prompt for a password since it is not a SQL login. Does not prompt for confirmation since -Confirm is set to $false.

    .EXAMPLE
        PS C:\> Reset-DbaAdmin -SqlInstance sqlserver\sqlexpress -Login sqladmin -Force

        Skips restart confirmation, prompts for password, then adds a SQL Login "sqladmin" with sysadmin privileges.
        If the account already exists, it will be added to the sysadmin role and the password will be reset.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWMICmdlet", "", Justification = "Using Get-WmiObject for client backwards compatibilty")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Login = "sa",
        [SecureString]$SecurePassword,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
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
                $connstring = "Data Source=$instance;Integrated Security=True;Connect Timeout=20;Application Name=Reset-DbaAdmin"
                $conn = New-Object System.Data.SqlClient.SqlConnection $connstring
                $conn.Open()
                $cmd = New-Object system.data.sqlclient.sqlcommand($null, $conn)
                $cmd.CommandText = $sql
                $cmd.ExecuteNonQuery() | Out-Null
                $cmd.Dispose()
                $conn.Close()
                $conn.Dispose()
                $true
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
        #endregion Utility functions
        if ($Force) {$ConfirmPreference = 'none'}

        if ($SqlCredential) {
            $Login = $SqlCredential.UserName
            $SecurePassword = $SqlCredential.Password
        }
    }

    process {
        foreach ($instance in $sqlinstance) {
            $stepcounter = 0
            $baseaddress = $instance.ComputerName
            # Get hostname

            if ($baseaddress.IsLocalHost) {
                $ipaddr = "."
                $hostname = $env:COMPUTERNAME
                $baseaddress = $env:COMPUTERNAME
            }

            # If server is not local, get IP address and NetBios name in case CNAME records were referenced in the SQL hostname
            if ($baseaddress -ne $env:COMPUTERNAME) {
                # Test for WinRM #Test-WinRM neh
                winrm id -r:$baseaddress 2>$null | Out-Null
                if ($LastExitCode -ne 0) {
                    Stop-Function -Continue -Message "Remote PowerShell access not enabled on on $instance or access denied. Quitting."
                }

                # Test Connection first using ping class which requires ICMP access then failback to tcp if pings are blocked
                Write-Message -Level Verbose -Message "Testing connection to $baseaddress"
                $ping = New-Object System.Net.NetworkInformation.Ping
                $timeout = 1000 #milliseconds
                $reply = $ping.Send($baseaddress, $timeout)
                if ($reply.Status -ne 'Success') {
                    Write-Message -Level Verbose -Message "First attempt using ICMP failed. Trying to connect using sockets. This may take up to 20 seconds."
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    try {
                        $tcp.Connect($hostname, 135)
                        $tcp.Close()
                        $tcp.Dispose()
                    } catch {
                        Stop-Function -Continue -ErrorRecord $_ -Message "Can't connect to $baseaddress either via ping or tcp (WMI port 135)"
                    }
                }
                Write-Message -Level Verbose -Message "Resolving IP address."
                try {
                    $hostentry = [System.Net.Dns]::GetHostEntry($baseaddress)
                    $ipaddr = ($hostentry.AddressList | Where-Object {
                            $_ -notlike '169.*'
                        } | Select-Object -First 1).IPAddressToString
                } catch {
                    Stop-Function -Continue -ErrorRecord $_ -Message "Could not resolve SqlServer IP or NetBIOS name"
                }

                Write-Message -Level Verbose -Message "Resolving NetBIOS name."
                try {
                    # this is required otherwise, the ip is returned
                    $hostname = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -ComputerName $ipaddr -ErrorAction Stop).PSComputerName
                    if ($null -eq $hostname) {
                        $hostname = (nbtstat -A $ipaddr | Where-Object {
                                $_ -match '\<00\>  UNIQUE'
                            } | ForEach-Object {
                                $_.SubString(4, 14)
                            }).Trim()
                    }
                } catch {
                    Stop-Function -Continue -ErrorRecord $_ -Message "Could not access remote WMI object. Check permissions and firewall."
                }
            }

            # Setup remote session if server is not local
            if (-not $instance.IsLocalHost) {
                try {
                    $connectionParams = @{
                        ComputerName = $hostname
                        ErrorAction  = "Stop"
                        UseSSL       = (Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.UseSSL' -Fallback $false)
                    }
                    $session = New-PSSession @connectionParams
                } catch {
                    Stop-Function -Continue -ErrorRecord $_ -Message "Can't access $hostname using PSSession. Check your firewall settings and ensure Remoting is enabled or run the script locally."
                }
            }

            Write-Message -Level Verbose -Message "Detecting login type."
            # Is login a Windows login? If so, does it exist?
            if ($login -match "\\") {
                Write-Message -Level Verbose -Message "Windows login detected. Checking to ensure account is valid."
                $windowslogin = $true
                try {
                    if ($hostname -eq $env:COMPUTERNAME) {
                        $account = New-Object System.Security.Principal.NTAccount($args)
                        #Variable $sid marked as unused by PSScriptAnalyzer replace with $null to catch output
                        $null = $account.Translate([System.Security.Principal.SecurityIdentifier])
                    } else {
                        Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $login -ScriptBlock {
                            $account = New-Object System.Security.Principal.NTAccount($args)
                            #Variable $sid marked as unused by PSScriptAnalyzer replace with $null to catch output
                            $null = $account.Translate([System.Security.Principal.SecurityIdentifier])
                        }
                    }
                } catch {
                    Write-Message -Level Warning -Message "Cannot resolve Windows User or Group $login. Trying anyway."
                }
            }

            # If it's not a Windows login, it's a SQL login, so it needs a password.
            if (-not $windowslogin -and -not $SecurePassword) {
                Write-Message -Level Verbose -Message "SQL login detected"
                do {
                    $Password = Read-Host -AsSecureString "Please enter a new password for $login"
                } while ($Password.Length -eq 0)
            }

            If ($SecurePassword) {
                $Password = $SecurePassword
            }

            # Get instance and service display name, then get services
            $instancename = $null
            $instancename = $instance.InstanceName
            if (-not $instancename) {
                $instancename = "MSSQLSERVER"
            }
            $displayName = "SQL Server ($instancename)"

            try {
                if ($hostname -eq $env:COMPUTERNAME) {
                    $instanceservices = Get-Service -ErrorAction Stop | Where-Object {
                        $_.DisplayName -like "*($instancename)*" -and $_.Status -eq "Running"
                    }
                    $sqlservice = Get-Service -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($instancename)"
                } else {
                    $instanceservices = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object {
                        $_.DisplayName -like "*($instancename)*" -and $_.Status -eq "Running"
                    }
                    $sqlservice = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($instancename)"
                }
            } catch {
                Stop-Function -Message "Cannot connect to WMI on $hostname or SQL Service does not exist. Check permissions, firewall and SQL Server running status." -ErrorRecord $_ -Target $instance
                return
            }

            if (-not $instanceservices) {
                Stop-Function -Message "Couldn't find SQL Server instance. Check the spelling, ensure the service is running and try again." -Target $instance
                return
            }

            Write-Message -Level Verbose -Message "Attempting to stop SQL Services."

            # Check to see if service is clustered. Clusters don't support -m (since the cluster service
            # itself connects immediately) or -f, so they are handled differently.
            try {
                $checkcluster = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object {
                    $_.Name -eq "ClusSvc" -and $_.Status -eq "Running"
                }
            } catch {
                Stop-Function -Message "Can't check services." -Target $instance -ErrorRecord $_
                return
            }

            if ($null -ne $checkcluster) {
                $clusterResource = Get-DbaCmObject -ClassName "MSCluster_Resource" -Namespace "root\mscluster" -ComputerName $hostname |
                    Where-Object {
                    $_.Name.StartsWith("SQL Server") -and $_.OwnerGroup -eq "SQL Server ($instancename)"
                }
            }


            if ($pscmdlet.ShouldProcess($baseaddress, "Stop $instance to restart in single-user mode")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Stopping $instance to restart in single-user mode"
                # Take SQL Server offline so that it can be started in single-user mode
                if ($clusterResource.count -gt 0) {
                    $isclustered = $true
                    try {
                        $clusterResource | Where-Object {
                            $_.Name -eq "SQL Server"
                        } | ForEach-Object {
                            $_.TakeOffline(60)
                        }
                    } catch {
                        $clusterResource | Where-Object {
                            $_.Name -eq "SQL Server"
                        } | ForEach-Object {
                            $_.BringOnline(60)
                        }
                        $clusterResource | Where-Object {
                            $_.Name -ne "SQL Server"
                        } | ForEach-Object {
                            $_.BringOnline(60)
                        }
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_ -Target $instance
                        return
                    }
                } else {
                    try {
                        Stop-Service -InputObject $sqlservice -Force -ErrorAction Stop
                        Write-Message -Level Verbose -Message "Successfully stopped SQL service."
                    } catch {
                        Start-Service -InputObject $instanceservices -ErrorAction Stop
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL service and quit." -ErrorRecord $_ -Target $instance
                        return
                    }
                }
            }

            # /mReset-DbaAdmin Starts an instance of SQL Server in single-user mode and only allows this script to connect.
            if ($pscmdlet.ShouldProcess($baseaddress, "Starting $instance in single-user mode")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Starting $instance in single-user mode"
                try {
                    if ($instance.IsLocalHost) {
                        $netstart = net start ""$displayname"" /mReset-DbaAdmin 2>&1
                        if ("$netstart" -notmatch "success") {
                            Stop-Function -Message "Restart failure" -Continue
                        }
                    } else {
                        $netstart = Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $displayname -ScriptBlock {
                            net start ""$args"" /mReset-DbaAdmin
                        } 2>&1
                        foreach ($line in $netstart) {
                            if ($line.length -gt 0) {
                                Write-Message -Level Verbose -Message $line
                            }
                        }
                    }
                } catch {
                    Stop-Service -InputObject $sqlservice -Force -ErrorAction SilentlyContinue

                    if ($isclustered) {
                        $clusterResource | Where-Object Name -eq "SQL Server" | ForEach-Object {
                            $_.BringOnline(60)
                        }
                        $clusterResource | Where-Object Name -ne "SQL Server" | ForEach-Object {
                            $_.BringOnline(60)
                        }
                    } else {
                        Start-Service -InputObject $instanceservices -ErrorAction SilentlyContinue
                    }
                    Stop-Function -Message "Couldn't execute net start command. Restarted services and quit." -ErrorRecord $_
                    return
                }
            }

            if ($pscmdlet.ShouldProcess($baseaddress, "Testing $instance to ensure it's back up")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Testing $instance to ensure it's back up"
                try {
                    $null = Invoke-ResetSqlCmd -instance $instance -Sql "SELECT 1" -EnableException
                } catch {
                    try {
                        Start-Sleep 3
                        $null = Invoke-ResetSqlCmd -instance $instance -Sql "SELECT 1" -EnableException
                    } catch {
                        Stop-Service Input-Object $sqlservice -Force -ErrorAction SilentlyContinue
                        if ($isclustered) {
                            $clusterResource | Where-Object {
                                $_.Name -eq "SQL Server"
                            } | ForEach-Object {
                                $_.BringOnline(60)
                            }
                            $clusterResource | Where-Object {
                                $_.Name -ne "SQL Server"
                            } | ForEach-Object {
                                $_.BringOnline(60)
                            }
                        } else {
                            Start-Service -InputObject $instanceservices -ErrorAction SilentlyContinue
                        }
                        Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_
                    }
                }
            }

            # Get login. If it doesn't exist, create it.
            if ($pscmdlet.ShouldProcess($instance, "Adding login $login if it doesn't exist")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding login $login if it doesn't exist"
                if ($windowslogin) {
                    $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$login')
                    BEGIN CREATE LOGIN [$login] FROM WINDOWS END"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't create Windows login."
                    }

                } elseif ($login -ne "sa") {
                    # Create new sql user
                    $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$login')
                    BEGIN CREATE LOGIN [$login] WITH PASSWORD = '$(ConvertTo-PlainText $Password)', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF END"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't create SQL login."
                    }
                }
            }


            # If $login is a SQL Login, Mixed mode authentication is required.
            if ($windowslogin -ne $true) {
                if ($pscmdlet.ShouldProcess($instance, "Enabling mixed mode authentication for $login and ensuring account is unlocked")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Enabling mixed mode authentication for $login and ensuring account is unlocked"
                    $sql = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't set to Mixed Mode."
                    }

                    $sql = "ALTER LOGIN [$login] WITH CHECK_POLICY = OFF
                    ALTER LOGIN [$login] WITH PASSWORD = '$(ConvertTo-PlainText $Password)' UNLOCK"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't unlock account."
                    }
                }
            }

            if ($pscmdlet.ShouldProcess($instance, "Enabling $login")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensuring login is enabled"
                $sql = "ALTER LOGIN [$login] ENABLE"
                if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                    Write-Message -Level Warning -Message "Couldn't enable login."
                }
            }

            if ($login -ne "sa") {
                if ($pscmdlet.ShouldProcess($instance, "Ensuring $login exists within sysadmin role")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensuring $login exists within sysadmin role"
                    $sql = "EXEC sp_addsrvrolemember '$login', 'sysadmin'"
                    if (-not (Invoke-ResetSqlCmd -instance $instance -Sql $sql)) {
                        Write-Message -Level Warning -Message "Couldn't add to sysadmin role."
                    }
                }
            }

            if ($pscmdlet.ShouldProcess($instance, "Finished with login tasks. Restarting")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Finished with login tasks. Restarting."
                try {
                    Stop-Service -InputObject $sqlservice -Force -ErrorAction Stop
                    if ($isclustered -eq $true) {
                        $clusterResource | Where-Object Name -eq "SQL Server" | ForEach-Object {
                            $_.BringOnline(60)
                        }
                        $clusterResource | Where-Object Name -ne "SQL Server" | ForEach-Object {
                            $_.BringOnline(60)
                        }
                    } else {
                        Start-Service -InputObject $instanceservices -ErrorAction Stop
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
            }

            if ($pscmdlet.ShouldProcess($instance, "Logging in to get account information")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Logging in to get account information"
                if ($securePassword) {
                    $cred = New-Object System.Management.Automation.PSCredential ($Login, $securePassword)
                    Get-DbaLogin -SqlInstance $instance -SqlCredential $cred -Login $Login
                } elseif ($SqlCredential) {
                    Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login
                } else {
                    try {
                        Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login -EnableException
                    } catch {
                        Stop-Function -Message "Password not supplied, tried logging in with Integrated authentication and it failed. Either way, $Login should work now on $instance." -Continue
                    }
                }
            }

        }
    }
    end {
        Write-Message -Level Verbose -Message "Script complete."
    }
}