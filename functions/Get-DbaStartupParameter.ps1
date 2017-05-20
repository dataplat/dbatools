Function Get-DbaStartupParameter {
<#
.SYNOPSIS
Displays values for a detailed list of SQL Server Startup Parameters.

.DESCRIPTION
Displays values for a detailed list of SQL Server Startup Parameters including Master Data Path, Master Log path, Error Log, Trace Flags, Parameter String and much more.

This command relies on remote Windows Server (SQL WMI/WinRm) access. You can pass alternative Windows credentials by using the -Credential parameter. 
	
See https://msdn.microsoft.com/en-us/library/ms190737.aspx for more information.
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the Windows Server as a different Windows user. 
	
.PARAMETER Simple
Shows a simplified output including only Server, Master Data Path, Master Log path, ErrorLog, TraceFlags and ParameterString

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: WSMan, SQLWMI, Memory
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Get-DbaStartupParameter

.EXAMPLE
Get-DbaStartupParameter -SqlInstance sql2014

Logs into SQL WMI as the current user then displays the values for numerous startup parameters.

.EXAMPLE
$wincred = Get-Credential ad\sqladmin
Get-DbaStartupParameter -SqlInstance sql2014 -Credential $wincred -Simple

Logs in to WMI using the ad\sqladmin credential and gathers simplified information about the SQL Server Startup Parameters.
	
#>	
	[CmdletBinding()]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[Alias("SqlCredential")]
		[PSCredential]$Credential,
		[switch]$Simple,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			try {
				if ($null -eq $instance.name) {
					$instance, $instancename = $instance.Split('\')
					$oginstance = $instance
				}
				else {
					$oginstance = $instance.name
					$instance, $instancename = $instance.name.Split('\')
				}
				
				$computername = (Resolve-DbaNetworkName $instance).ComputerName
				
				Write-Message -Level Verbose -message "Attempting to connect to $computername"
				
				if ($instancename.Length -eq 0) { $instancename = "MSSQLSERVER" }
				
				$displayname = "SQL Server ($instancename)"
				
				$Scriptblock = {
					$computername = $args[0]
					$displayname = $args[1]
					
					$wmisvc = $wmi.Services | Where-Object { $_.DisplayName -eq $displayname }
					
					$params = $wmisvc.StartupParameters -split ';'
					
					$masterdata = $params | Where-Object { $_.StartsWith('-d') }
					$masterlog = $params | Where-Object { $_.StartsWith('-l') }
					$errorlog = $params | Where-Object { $_.StartsWith('-e') }
					$traceflags = $params | Where-Object { $_.StartsWith('-T') }
					
					$debugflag = $params | Where-Object { $_.StartsWith('-t') }
					
					<#
					if ($debugflag.length -ne 0) {
						Write-Message -Level Warning "$instance is using the lowercase -t trace flag. This is for internal debugging only. Please ensure this was intentional."
					}
					#>
					
					if ($traceflags.length -eq 0) {
						$traceflags = "None"
					}
					else {
						$traceflags = $traceflags.substring(2)
					}
					
					if ($Simple -eq $true) {
						[PSCustomObject]@{
							ComputerName = $computername
							InstanceName = $instancename
							SqlInstance = $oginstance
							MasterData = $masterdata.TrimStart('-d')
							MasterLog = $masterlog.TrimStart('-l')
							ErrorLog = $errorlog.TrimStart('-e')
							TraceFlags = $traceflags -join ','
							ParameterString = $wmisvc.StartupParameters
						}
					}
					else {
						# From https://msdn.microsoft.com/en-us/library/ms190737.aspx
						
						$commandpromptparm = $params | Where-Object { $_ -eq '-c' }
						$minimalstartparm = $params | Where-Object { $_ -eq '-f' }
						$memorytoreserve = $params | Where-Object { $_.StartsWith('-g') }
						$noeventlogsparm = $params | Where-Object { $_ -eq '-n' }
						$instancestartparm = $params | Where-Object { $_ -eq '-s' }
						$disablemonitoringparm = $params | Where-Object { $_ -eq '-x' }
						$increasedextentsparm = $params | Where-Object { $_ -ceq '-E' }
						
						$minimalstart = $noeventlogs = $instancestart = $disablemonitoring = $false
						$increasedextents = $commandprompt = $singleuser = $false
						
						if ($commandpromptparm -ne $null) { $commandprompt = $true }
						if ($minimalstartparm -ne $null) { $minimalstart = $true }
						if ($memorytoreserve -eq $null) { $memorytoreserve = 0 }
						if ($noeventlogsparm -ne $null) { $noeventlogs = $true }
						if ($instancestartparm -ne $null) { $instancestart = $true }
						if ($disablemonitoringparm -ne $null) { $disablemonitoring = $true }
						if ($increasedextentsparm -ne $null) { $increasedextents = $true }
						
						$singleuserparm = $params | Where-Object { $_.StartsWith('-m') }
						
						if ($singleuserparm.length -ne 0) {
							$singleuser = $true
							$singleuserdetails = $singleuserparm.TrimStart('-m')
							# It's possible the person specified an application name
							# if not, just say that single user is $true
							#	if ($singleuserdetails.length -ne 0)
							#	{
							#		$singleuser = $singleuserdetails
							#	}
						}
						
						[PSCustomObject]@{
							ComputerName = $computername
							InstanceName = $instancename
							SqlInstance = $oginstance
							MasterData = $masterdata.TrimStart('-d')
							MasterLog = $masterlog.TrimStart('-l')
							ErrorLog = $errorlog.TrimStart('-e')
							TraceFlags = $traceflags -join ','
							CommandPromptStart = $commandprompt
							MinimalStart = $minimalstart
							MemoryToReserve = $memorytoreserve
							SingleUser = $singleuser
							SingleUserName = $singleuserdetails
							NoLoggingToWinEvents = $noeventlogs
							StartAsNamedInstance = $instancestart
							DisableMonitoring = $disablemonitoring
							IncreasedExtents = $increasedextents
							ParameterString = $wmisvc.StartupParameters
						}
					}
				}
				
				# This command is in the internal function
				# It's sorta like Invoke-Command. 
				if ($credential) {
					Invoke-ManagedComputerCommand -Server $computername -Credential $credential -ScriptBlock $Scriptblock -ArgumentList $instance, $displayname
				}
				else {
					Invoke-ManagedComputerCommand -Server $computername -ScriptBlock $Scriptblock -ArgumentList $instance, $displayname
				}
			}
			catch {
				Write-Message -Level Warning -Message "$instance failed with the following error: $_"
			}
		}
	}
}
