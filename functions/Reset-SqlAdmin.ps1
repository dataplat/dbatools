Function Reset-SqlAdmin
{
<# 
.SYNOPSIS 
This function will allow administrators to regain access to SQL Servers in the event that passwords or access was lost.

Supports SQL Server 2005 and above. Windows administrator access is required.

.DESCRIPTION
This function allows administrators to regain access to local or remote SQL Servers by either resetting the sa password, adding sysadmin role to existing login,
or adding a new login (SQL or Windows) and granting it sysadmin privileges.

This is accomplished by stopping the SQL services or SQL Clustered Resource Group, then restarting SQL via the command-line
using the /mReset-SqlAdmin paramter which starts the server in Single-User mode, and only allows this script to connect.

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


.PARAMETER SqlServer
The SQL Server instance. SQL Server must be 2005 and above, and can be a clustered or stand-alone instance.

.PARAMETER Login
By default, the Login parameter is "sa" but any other SQL or Windows account can be specified. If a login does not
currently exist, it will be added.

When adding a Windows login to remote servers, ensure the SQL Server can add the login (ie, don't add WORKSTATION\Admin to remoteserver\instance. Domain users and 
Groups are valid input.

.PARAMETER Force
By default, a confirmation is presented to ensure the person executing the script knows that a service restart will occur. Force basically performs a -Confirm:$false. This will restart the SQL Service without prompting.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: Admin access to server (not SQL Services), 
Remoting must be enabled and accessible if $sqlserver is not local

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Reset-SqlAdmin 

.EXAMPLE   
Reset-SqlAdmin -SqlServer sqlcluster

Prompts for password, then resets the "sa" account password on sqlcluster.

.EXAMPLE   
Reset-SqlAdmin -SqlServer sqlserver\sqlexpress -Login ad\administrator

Prompts user to confirm that they understand the SQL Service will be restarted.

Adds the domain account "ad\administrator" as a sysadmin to the SQL instance. 
If the account already exists, it will be added to the sysadmin role.

.EXAMPLE   
Reset-SqlAdmin -SqlServer sqlserver\sqlexpress -Login sqladmin -Force

Skips restart confirmation, prompts for passsword, then adds a SQL Login "sqladmin" with sysadmin privleges. 
If the account already exists, it will be added to the sysadmin role and the password will be reset.

#>	
	[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[string]$SqlServer,
		[string]$Login = "sa",
		[switch]$Force
	)
	
	BEGIN
	{
		Function ConvertTo-PlainText
		{
<#
.SYNOPSIS
Internal function.
			
 #>
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[Security.SecureString]$Password
			)
			
			$marshal = [Runtime.InteropServices.Marshal]
			$plaintext = $marshal::PtrToStringAuto($marshal::SecureStringToBSTR($Password))
			return $plaintext
		}
		
		Function Invoke-ResetSqlCmd
		{
		<#

		.SYNOPSIS
		Internal function. Executes a SQL statement against specified computer, and uses "Reset-SqlAdmin" as the
		Application Name.
					
		 #>
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[Alias("ServerInstance","SqlInstance")]
				[string]$sqlserver,
				[string]$sql
			)
			try
			{
				$connstring = "Data Source=$sqlserver;Integrated Security=True;Connect Timeout=2;Application Name=Reset-SqlAdmin"
				$conn = New-Object System.Data.SqlClient.SqlConnection $connstring
				$conn.Open()
				$cmd = New-Object system.data.sqlclient.sqlcommand($null, $conn)
				$cmd.CommandText = $sql
				$cmd.ExecuteNonQuery() | Out-Null
				$cmd.Dispose()
				$conn.Close()
				$conn.Dispose()
				return $true
			}
			catch
			{
				return $false
			}
		}
	}
	
	PROCESS
	{
			if ($Force) { $ConfirmPreference="none" }
			
			$baseaddress = $sqlserver.Split("\")[0]

	        # Before we continue, we need confirmation.
	        if ($pscmdlet.ShouldProcess($baseaddress, "Reset-SqlAdmin (SQL Server instance $sqlserver will restart)"))
	        {
			# Get hostname
			
			if ($baseaddress -eq "." -or $baseaddress -eq $env:COMPUTERNAME -or $baseaddress -eq "localhost")
			{
				$ipaddr = "."
				$hostname = $env:COMPUTERNAME
				$baseaddress = $env:COMPUTERNAME
			}
			
			# If server is not local, get IP address and NetBios name in case CNAME records were referenced in the SQL hostname
			if ($baseaddress -ne $env:COMPUTERNAME)
			{
				# Test for WinRM #Test-WinRM neh
				winrm id -r:$baseaddress 2>$null | Out-Null
				if ($LastExitCode -ne 0)
				{
					throw "Remote PowerShell access not enabled on on $source or access denied. Quitting."
				}
				
				# Test Connection first using Test-Connection which requires ICMP access then failback to tcp if pings are blocked
				Write-Output "Testing connection to $baseaddress"
				$testconnect = Test-Connection -ComputerName $baseaddress -Count 1 -Quiet
				
				if ($testconnect -eq $false)
				{
					Write-Output "First attempt using ICMP failed. Trying to connect using sockets. This may take up to 20 seconds."
					$tcp = New-Object System.Net.Sockets.TcpClient
					try
					{
						$tcp.Connect($hostname, 135)
						$tcp.Close()
						$tcp.Dispose()
					}
					catch
					{
						throw "Can't connect to $baseaddress either via ping or tcp (WMI port 135)"
					}
				}
				Write-Output "Resolving IP address"
				try
				{
					$hostentry = [System.Net.Dns]::GetHostEntry($baseaddress)
					$ipaddr = ($hostentry.AddressList | Where-Object { $_ -notlike '169.*' } | Select -First 1).IPAddressToString
				}
				catch
				{
					throw "Could not resolve SqlServer IP or NetBIOS name"
				}
				
				Write-Output "Resolving NetBIOS name"
				try
				{
					$hostname = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -ComputerName $ipaddr).PSComputerName
					if ($hostname -eq $null) { $hostname = (nbtstat -A $ipaddr | Where-Object { $_ -match '\<00\>  UNIQUE' } | ForEach-Object { $_.SubString(4, 14) }).Trim() }
				}
				catch
				{
					throw "Could not access remote WMI object. Check permissions and firewall."
				}
			}
			
			# Setup remote session if server is not local
			if ($hostname -ne $env:COMPUTERNAME)
			{
				try
				{
					$session = New-PSSession -ComputerName $hostname
				}
				catch
				{
					throw "Can't access $hostname using PSSession. Check your firewall settings and ensure Remoting is enabled or run the script locally."
				}
			}
			
			Write-Output "Detecting login type"
			# Is login a Windows login? If so, does it exist? 
			if ($login -match "\\")
			{
				Write-Output "Windows login detected. Checking to ensure account is valid."
				$windowslogin = $true
				try
				{
					if ($hostname -eq $env:COMPUTERNAME)
					{
						$account = New-Object System.Security.Principal.NTAccount($args)
						$sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
					}
					else
					{
						Invoke-Command -ErrorAction Stop -Session $session -Args $login -ScriptBlock {
							$account = New-Object System.Security.Principal.NTAccount($args)
							$sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
						}
					}
				}
				catch { Write-Warning "Cannot resolve Windows User or Group $login. Trying anyway." }
			}
			
			# If it's not a Windows login, it's a SQL login, so it needs a password.
			if ($windowslogin -ne $true)
			{
				Write-Output "SQL login detected"
				do { $Password = Read-Host -AsSecureString "Please enter a new password for $login" }
				while ($Password.Length -eq 0)
			}
			
			# Get instance and service display name, then get services
			$instance = ($sqlserver.split("\"))[1]
			if ($instance -eq $null) { $instance = "MSSQLSERVER" }
			$displayName = "SQL Server ($instance)"
			
			try
			{
				if ($hostname -eq $env:COMPUTERNAME)
				{
					$instanceservices = Get-Service | Where-Object { $_.DisplayName -like "*($instance)*" -and $_.Status -eq "Running" }
					$sqlservice = Get-Service | Where-Object { $_.DisplayName -eq "SQL Server ($instance)" }
				}
				else
				{
					$instanceservices = Get-Service -ComputerName $ipaddr | Where-Object { $_.DisplayName -like "*($instance)*" -and $_.Status -eq "Running" }
					$sqlservice = Get-Service -ComputerName $ipaddr | Where-Object { $_.DisplayName -eq "SQL Server ($instance)" }
				}
			}
			catch
			{
				throw "Cannot connect to WMI on $hostname or SQL Service does not exist. Check permissions, firewall and SQL Server running status."
			}
			
			if ($instanceservices -eq $null)
			{
				throw "Couldn't find SQL Server instance. Check the spelling, ensure the service is running and try again."
			}
			
			Write-Output "Attempting to stop SQL Services"
			
			# Check to see if service is clustered. Clusters don't support -m (since the cluster service
			# itself connects immediately) or -f, so they are handled differently.
			try
			{
				$checkcluster = Get-Service -ComputerName $ipaddr | Where-Object { $_.Name -eq "ClusSvc" -and $_.Status -eq "Running" }
			}
			catch
			{
				throw "Can't check services. Check permissions and firewall."
			}
			
			if ($checkcluster -ne $null)
			{
				$clusterResource = Get-WmiObject -Authentication PacketPrivacy -Impersonation Impersonate -class "MSCluster_Resource" -namespace "root\mscluster" -computername $hostname |
				Where-Object { $_.Name.StartsWith("SQL Server") -and $_.OwnerGroup -eq "SQL Server ($instance)" }
			}
			
			# Take SQL Server offline so that it can be started in single-user mode
			if ($clusterResource.count -gt 0)
			{
				$isclustered = $true
				try
				{
					$clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.TakeOffline(60) }
				}
				catch
				{
					$clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
					$clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
					throw "Could not stop the SQL Service. Restarted SQL Service and quit."
				}
			}
			else
			{
				try
				{
					Stop-Service -InputObject $sqlservice -Force
					Write-Output "Successfully stopped SQL service"
				}
				catch
				{
					Start-Service -InputObject $instanceservices
					throw "Could not stop the SQL Service. Restarted SQL service and quit."
				}
			}
			
			# /mReset-SqlAdmin Starts an instance of SQL Server in single-user mode and only allows this script to connect.
			Write-Output "Starting SQL Service from command line"
			try
			{
				if ($hostname -eq $env:COMPUTERNAME)
				{
					$netstart = net start ""$displayname"" /mReset-SqlAdmin 2>&1
					if ("$netstart" -notmatch "success") { throw }
				}
				else
				{
					$netstart = Invoke-Command -ErrorAction Stop -Session $session -Args $displayname -ScriptBlock { net start ""$args"" /mReset-SqlAdmin } 2>&1
					foreach ($line in $netstart)
					{
						if ($line.length -gt 0) { Write-Output $line }
					}
				}
			}
			catch
			{
				Stop-Service -InputObject $sqlservice -Force -ErrorAction SilentlyContinue
				
				if ($isclustered)
				{
					$clusterResource | Where-Object Name -eq "SQL Server" | ForEach-Object { $_.BringOnline(60) }
					$clusterResource | Where-Object Name -ne "SQL Server" | ForEach-Object { $_.BringOnline(60) }
				}
				else
				{
					Start-Service -InputObject $instanceservices -ErrorAction SilentlyContinue
				}
				throw "Couldn't execute net start command. Restarted services and quit."
			}
			
			Write-Output "Reconnecting to SQL instance"
			try
			{
				Invoke-ResetSqlCmd -SqlServer $sqlserver -Sql "SELECT 1" | Out-Null
			}
			catch
			{
				try
				{
					Start-Sleep 3
					Invoke-ResetSqlCmd -SqlServer $sqlserver -Sql "SELECT 1" | Out-Null
				}
				catch
				{
					Stop-Service Input-Object $sqlservice -Force -ErrorAction SilentlyContinue
					if ($isclustered)
					{
						$clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
						$clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
					}
					else { Start-Service -InputObject $instanceservices -ErrorAction SilentlyContinue }
					throw "Could not stop the SQL Service. Restarted SQL Service and quit."
				}
			}
			
			# Get login. If it doesn't exist, create it.
			Write-Output "Adding login $login if it doesn't exist"
			if ($windowslogin -eq $true)
			{
				$sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$login')
					BEGIN CREATE LOGIN [$login] FROM WINDOWS END"
				if ($(Invoke-ResetSqlCmd -SqlServer $sqlserver -Sql $sql) -eq $false) { Write-Error "Couldn't create login." }
			}
			elseif ($login -ne "sa")
			{
				# Create new sql user
				$sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$login')
					BEGIN CREATE LOGIN [$login] WITH PASSWORD = '$(ConvertTo-PlainText $Password)', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF END"
				if ($(Invoke-ResetSqlCmd -SqlServer $sqlserver -Sql $sql) -eq $false) { Write-Error "Couldn't create login." }
			}
			
			# If $login is a SQL Login, Mixed mode authentication is required.
			if ($windowslogin -ne $true)
			{
				Write-Output "Enabling mixed mode authentication"
				Write-Output "Ensuring account is unlocked"
				$sql = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2"
				if ($(Invoke-ResetSqlCmd -SqlServer $sqlserver -Sql $sql) -eq $false) { Write-Error "Couldn't set to Mixed Mode." }
				
				$sql = "ALTER LOGIN [$login] WITH CHECK_POLICY = OFF
					ALTER LOGIN [$login] WITH PASSWORD = '$(ConvertTo-PlainText $Password)' UNLOCK"
				if ($(Invoke-ResetSqlCmd -SqlServer $sqlserver -Sql $sql) -eq $false) { Write-Error "Couldn't unlock account." }
			}
			
			Write-Output "Ensuring login is enabled"
			$sql = "ALTER LOGIN [$login] ENABLE"
			if ($(Invoke-ResetSqlCmd -SqlServer $sqlserver -Sql $sql) -eq $false) { Write-Error "Couldn't enable login." }
			
			if ($login -ne "sa")
			{
				Write-Output "Ensuring login exists within sysadmin role"
				$sql = "EXEC sp_addsrvrolemember '$login', 'sysadmin'"
				if ($(Invoke-ResetSqlCmd -SqlServer $sqlserver -Sql $sql) -eq $false) { Write-Error "Couldn't add to syadmin role." }
			}
			
			Write-Output "Finished with login tasks"
			Write-Output "Restarting SQL Server"
			Stop-Service -InputObject $sqlservice -Force -ErrorAction SilentlyContinue
			if ($isclustered -eq $true)
			{
				$clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
				$clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
			}
			else { Start-Service -InputObject $instanceservices -ErrorAction SilentlyContinue }
		}
	}
	END
	{
		Write-Output "Script complete!"
	}
}
