#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Test-DbaConnection {
	<#
		.SYNOPSIS
			Exported function. Tests a the connection to a single instance and shows the output.

		.DESCRIPTION
			Tests a the connection to a single instance and shows the output.

		.PARAMETER SqlInstance
			The SQL Server Instance to test connection against

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Silent
			Replaces user friendly yellow warnings with bloody red exceptions of doom!
			Use this if you want the function to throw terminating errors you want to catch.

		.EXAMPLE
			Test-DbaConnection sql01

			Sample output:

			Local PowerShell Enviornment

			Windows    : 10.0.10240.0
			PowerShell : 5.0.10240.16384
			CLR        : 4.0.30319.42000
			SMO        : 13.0.0.0
			DomainUser : True
			RunAsAdmin : False

			SQL Server Connection Information

			ServerName         : sql01
			BaseName           : sql01
			InstanceName       : (Default)
			AuthType           : Windows Authentication (Trusted)
			ConnectingAsUser   : ad\dba
			ConnectSuccess     : True
			SqlServerVersion   : 12.0.2370
			AddlConnectInfo    : N/A
			RemoteServer       : True
			IPAddress          : 10.0.1.4
			NetBIOSname        : SQLSERVER2014A
			RemotingAccessible : True
			Pingable           : True
			DefaultSQLPortOpen : True
			RemotingPortOpen   : True

		.NOTES
			Tags: CIM
			Original Author: Chrissy LeMaire
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
	#>
		[CmdletBinding()]
		param (
			[Parameter(Mandatory = $true)]
			[Alias("ServerInstance", "SqlServer")]
			[DbaInstance[]]$SqlInstance,
			[PSCredential]$Credential,
			[PSCredential]$SqlCredential,
			[switch]$Silent
		)
		process {
			foreach ($instance in $SqlInstance) {
				# Get local enviornment
				Write-Message -Level Verbose -Message "Getting local enivornment information"
				$localinfo = [pscustomobject]@{
					Windows = [environment]::OSVersion.Version.ToString()
					PowerShell = $PSVersionTable.PSversion.ToString()
					CLR = $PSVersionTable.CLRVersion.ToString()
					SMO = ((([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }).FullName -Split ", ")[1]).TrimStart("Version=")
					DomainUser = $env:computername -ne $env:USERDOMAIN
					RunAsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
				}

				$serverInfo = [pscustomobject]@{
					IsDefault = if ( $instance.Type -eq 'Default') { $true } else { $false }
					IsRemote = [DbaValidate]::IsLocalHost($env:computername)
				}

				try {
					<# gather following properties #>
					<#
						InputName        :
						ComputerName     :
						IPAddress        :
						DNSHostName      :
						DNSDomain        :
						Domain           :
						DNSHostEntry     :
						FQDN             :
						FullComputerName :
					 #>
					$resolved = Resolve-DbaNetworkName -ComputerName $instance.ComputerName -Credential $SqlCredential
				}
				catch {
					Stop-Function -Message "Unable to resolve server information" -Category ConnectionError -Target $instance -ErrorRecord $_ -Continue
				}

				if ($remote -eq $true) {
					# Test for WinRM #Test-WinRM neh
					Write-Message -Level Verbose -Message "Checking remote acccess"
					winrm id -r:$hostname 2>$null | Out-Null
					if ($LastExitCode -eq 0) { $remoting = $true }
					else { $remoting = $false }

					Add-Member -Force -InputObject $serverInfo -MemberType NoteProperty -Name RemotingAccessible -Value $remoting

					Write-Message -Level Verbose -Message "Testing raw socket connection to PowerShell remoting port"
					$tcp = New-Object System.Net.Sockets.TcpClient
					try {
						$tcp.Connect($baseaddress, 135)
						$tcp.Close()
						$tcp.Dispose()
						$remotingport = $true
					}
					catch { $remotingport = $false }

					Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name RemotingPortOpen -Value $remotingport
				}

				# Test Connection first using Test-Connection which requires ICMP access then failback to tcp if pings are blocked
				Write-Message -Level Verbose -Message "Testing ping to $($instance.ComputerName)"
				$pingable = Test-Connection -ComputerName $instance.ComputerName -Count 1 -Quiet
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name IsPingable -Value $pingable

				# SQL Server connection
				if ($instance -eq "(Default)") {
					Write-Message -Level Verbose -Message "Testing raw socket connection to default SQL port"
					$tcp = New-Object System.Net.Sockets.TcpClient
					try {
						$tcp.Connect($baseaddress, 1433)
						$tcp.Close()
						$tcp.Dispose()
						$sqlport = $true
					}
					catch {
						$sqlport = $false
					}
					Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name DefaultSqlPortOpen -Value $sqlport
				}
				else {
					Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name DefaultSqlPortOpen -Value "N/A"
				}

				try {
					$server = Connect-SqlInstance -SqlInstance $instance.FullSmoName -SqlCredential $SqlCredential
					$connectSuccess = $true
				}
				catch {
					$connectSuccess = $false
					Stop-Function -Message "Issue connection to SQL Server on $instance" -Category ConnectionError -Target $instance -ErrorRecord $_ -Continue
				}

				$username = $server.ConnectionContext.TrueLogin
				if ($username -like "*\*") {
					$authType = "Windows Authentication"
				}
				else {
					$authType = "SQL Authentication"
				}
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name ComputerName -Value $resolved.ComputerName
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name InstanceName -Value $instance.InstanceName
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name SqlInstance -Value $instance.FullSmoName

				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name ConnectingAsUser -Value $username
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name AuthType -Value $authType
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name ConnectSuccess -Value $connectSuccess
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name SqlServerVersion -Value $server.Version

				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name LocalWindows -Value $localinfo.Windows
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name LocalPowerShell -Value $localinfo.PowerShell
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name LocalCLR -Value $localinfo.CLR
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name LocalSMOVersion -Value $localinfo.SMO
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name LocalDomainUser -Value $localinfo.DomainUser
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name LocalRunAsAdmin -Value $localinfo.RunAsAdmin

				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name IPAddress -Value $resolved.IPAddress
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name NetBiosName -Value $resolved.FullComputerName
				Add-Member -Force -InputObject $serverinfo -MemberType NoteProperty -Name DomainName -Value $resolved.Domain

				$defaults = 'ComputerName', 'InstanceName', 'SqlInstance',
					'IsDefault','AuthType', 'ConnectingAsUser', 'ConnectSuccess',
					'SqlServerVersion', 'DefaultSqlPortOpen', 'IPAddress', 'NetBIOSname', 'DomainName',
					'IsPingable', 'IsRemote', 'RemotingAccessible', 'RemotingPortOpen'
				Select-DefaultView -InputObject $serverInfo -Property $defaults
			}
		}
		end {
			Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Test-SqlConnection
		}
	}
