function Set-DbaStartupParameter {
<#
.SYNOPSIS
Sets the Startup Parameters for a SQL Server instance

.DESCRIPTION
Modifies the startup parameters for a specified SQL Server SqlInstance

For full details of what each parameter does, please refer to this MSDN article - https://msdn.microsoft.com/en-us/library/ms190737(v=sql.105).aspx

.PARAMETER SqlInstance
The SQL Server instance to be modified

.PARAMETER Credential
Windows credential with permission to log on to the server running the SQL instance

.PARAMETER MasterData
Path to the data file for the Master database

.PARAMETER MasterLog
Path to the log file for the Master database

.PARAMETER ErrorLog
path to the SQL Server error log file 

.PARAMETER TraceFlags
A comma seperated list of TraceFlags to be applied at SQL Server startup
By default these will be appended to any existing trace flags set

.PARAMETER CommandPromptStart
	
Shortens startup time when starting SQL Server from the command prompt. Typically, the SQL Server Database Engine starts as a service by calling the Service Control Manager. 
Because the SQL Server Database Engine does not start as a service when starting from the command prompt

.PARAMETER MinimalStart
	
Starts an instance of SQL Server with minimal configuration. This is useful if the setting of a configuration value (for example, over-committing memory) has 
prevented the server from starting. Starting SQL Server in minimal configuration mode places SQL Server in single-user mode

.PARAMETER MemoryToReserve
Specifies an integer number of megabytes (MB) of memory that SQL Server will leave available for memory allocations within the SQL Server process, 
but outside the SQL Server memory pool. The memory outside of the memory pool is the area used by SQL Server for loading items such as extended procedure .dll files, 
the OLE DB providers referenced by distributed queries, and automation objects referenced in Transact-SQL statements. The default is 256 MB.

.PARAMETER SingleUser
Start Sql Server in single user mode

.PARAMETER NoLoggingToWinEvents
Don't use Windows Application events log

.PARAMETER StartAsNamedInstance
Allows you to start a named instance of SQL Server

.PARAMETER DisableMonitoring
Disables the following monitoring features:

SQL Server performance monitor counters
Keeping CPU time and cache-hit ratio statistics
Collecting information for the DBCC SQLPERF command
Collecting information for some dynamic management views
Many extended-events event points

** Warning *\* When you use the –x startup option, the information that is available for you to diagnose performance and functional problems with SQL Server is greatly reduced.
	
.PARAMETER SingleUserDetails
The username for single user
	
.PARAMETER IncreasedExtents
Increases the number of extents that are allocated for each file in a filegroup. 

.PARAMETER TraceFlagsOverride
Overrides the default behaviour and replaces any existing trace flags. If not trace flags specified will just remove existing ones

.PARAMETER StartUpConfig
Pass in a previously saved SQL Instance startUpconfig
using this parameter will set TraceFlagsOverride to true, so existing Trace Flags will be overridden

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE 
Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser

Will configure the SQL Instance server1\instance1 to startup up in Single User mode at next startup
	
.EXAMPLE 
Set-DbaStartupParameter -SqlInstance sql2016 -IncreasedExtents

Will configure the SQL Instance sql2016 to IncreasedExtents = True (-E)

.EXAMPLE 
Set-DbaStartupParameter -SqlInstance sql2016  -IncreasedExtents:$false -WhatIf

Shows what would happen if you attempted to configure the SQL Instance sql2016 to IncreasedExtents = False (no -E)

.EXAMPLE
Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -TraceFlags 8032,8048
This will appened Trace Flags 8032 and 8048 to the startup parameters

.EXAMPLE
Set-DbaStartupParameter -SqlInstance sql2016 -SingleUser:$false -TraceFlagsOverride
This will remove all trace flags and set SinguleUser to false
	
.EXAMPLE
Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -TraceFlags 8032,8048 -TraceFlagsOverride

This will set Trace Flags 8032 and 8048 to the startup parameters, removing any existing Trace Flags

.EXAMPLE

$StartupConfig = Get-DbaStartupParameter -SqlInstance server1\instance1
Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -NoLoggingToWinEvents
#Restart your SQL instance with the tool of choice
#Do Some work
Set-DbaStartupParameter -SqlInstance server1\instance1 -StartUpConfig $StartUpConfig
#Restart your SQL instance with the tool of choice and you're back to normal

In this example we take a copy of the existing startup configuration of server1\instance1

We then change the startup parameters ahead of some work

After the work has been completed, we can push the original startup parameters back to server1\instance1 and resume normal operation

#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	param ([parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[PSCredential]$Credential,
		[string]$MasterData,
		[string]$MasterLog,
		[string]$ErrorLog,
		[string[]]$TraceFlags,
		[switch]$CommandPromptStart,
		[switch]$MinimalStart,
		[int]$MemoryToReserve,
		[switch]$SingleUser,
		[string]$SingleUserDetails,
		[switch]$NoLoggingToWinEvents,
		[switch]$StartAsNamedInstance,
		[switch]$DisableMonitoring,
		[switch]$IncreasedExtents,
		[switch]$TraceFlagsOverride,
		[object]$StartUpConfig,
		[switch]$Silent
		
	)
	process {
		
		#Get Current parameters:
		$currentstartup = Get-DbaStartupParameter -SqlInstance $sqlinstance -Credential $Credential
		$originalparamstring = $currentstartup.ParameterString
		
		Write-Message -Level Output -Message "Original startup parameter string: $originalparamstring"
		
		if ('startUpconfig' -in $PsBoundParameters.keys) {
			Write-Message -Level VeryVerbose -Message "StartupObject passed in"
			$newstartup = $StartUpConfig
			$TraceFlagsOverride = $true
		}
		else {
			Write-Message -Level VeryVerbose -Message "Parameters passed in"
			$newstartup = $currentstartup.PSObject.copy()
			foreach ($param in ($PsBoundParameters.keys | Where-Object { $_ -in ($newstartup.PSObject.Properties.name) })) {
				if ($PsBoundParameters.item($param) -ne $newstartup.$param) {
					$newstartup.$param = $PsBoundParameters.item($param)
				}
			}
		}
		
		if (!($currentstartup.SingleUser)) {
			
			if ($newstartup.Masterdata.length -gt 0) {
				if (Test-DbaSqlPath -SqlInstance $sqlinstance -SqlCredential $Credential -Path (Split-Path $newstartup.MasterData -Parent)) {
					$ParameterString += "-d$($newstartup.MasterData);"
				}
				else {
					Stop-Function -Message "Specified folder for Master Data file is not reachable by instance $sqlinstance"
				}
			}
			else {
				Stop-Function -Message "MasterData value must be provided"
			}
			
			if ($newstartup.ErrorLog.length -gt 0) {
				if (Test-DbaSqlPath -SqlInstance $sqlinstance -SqlCredential $Credential -Path (Split-Path $newstartup.ErrorLog -Parent)) {
					$ParameterString += "-e$($newstartup.ErrorLog);"
				}
				else {
					Stop-Function -Message "Specified folder for ErrorLog  file is not reachable by $sqlinstance"
				}
			}
			else {
				Stop-Function -Message "ErrorLog value must be provided"
			}
			
			if ($newstartup.MasterLog.Length -gt 0) {
				if (Test-DbaSqlPath -SqlInstance $sqlinstance -SqlCredential $Credential -Path (Split-Path $newstartup.MasterLog -Parent)) {
					$ParameterString += "-l$($newstartup.MasterLog);"
				}
				else {
					Stop-Function -Message "Specified folder for Master Log  file is not reachable by $sqlinstance"
				}
			}
			else {
				Stop-Function -Message "MasterLog value must be provided."
			}
		}
		else {
			
			Write-Message -Level Verbose -Message "Sql instance is presently configured for single user, skipping path validation"
			if ($newstartup.MasterData.Length -gt 0) {
				$ParameterString += "-d$($newstartup.MasterData);"
			}
			else {
				Stop-Function -Message "Must have a value for MasterData"
			}
			if ($newstartup.ErrorLog.Length -gt 0) {
				$ParameterString += "-e$($newstartup.ErrorLog);"
			}
			else {
				Stop-Function -Message "Must have a value for Errorlog"
			}
			if ($newstartup.MasterLog.Length -gt 0) {
				$ParameterString += "-l$($newstartup.MasterLog);"
			}
			else {
				Stop-Function -Message "Must have a value for MsterLog"
			}
		}
		
		if ($newstartup.CommandPromptStart) {
			$ParameterString += "-c;"
		}
		if ($newstartup.MinimalStart) {
			$ParameterString += "-f;"
		}
		if ($newstartup.MemoryToReserve -notin ($null, 0)) {
			$ParameterString += "-g$($newstartup.MemoryToReserve)"
		}
		if ($newstartup.SingleUser) {
			if ($SingleUserDetails.length -gt 0) {
				if ($SingleUserDetails -match ' ') {
					$SingleUserDetails = """$SingleUserDetails"""
				}
				$ParameterString += "-m$SingleUserDetails;"
			}
			else {
				$ParameterString += "-m;"
			}
		}
		if ($newstartup.NoLoggingToWinEvents) {
			$ParameterString += "-n;"
		}
		If ($newstartup.StartAsNamedInstance) {
			$ParameterString += "-s;"
		}
		if ($newstartup.DisableMonitoring) {
			$ParameterString += "-x;"
		}
		if ($newstartup.IncreasedExtents) {
			$ParameterString += "-E;"
		}
		if ($newstartup.TraceFlags -eq 'None') {
			$newstartup.TraceFlags = ''
		}
		if ($TraceFlagsOverride -and 'TraceFlags' -in $PsBoundParameters.keys) {
			if ($null -ne $TraceFlags -and '' -ne $TraceFlags) {
				$newstartup.TraceFlags = $TraceFlags -join ','
				$ParameterString += (($TraceFlags.split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
			}
		}
		else {
			if ('TraceFlags' -in $PsBoundParameters.keys) {
				if ($null -eq $TraceFlags) { $TraceFlags = '' }
				$oldflags = @($currentstartup.TraceFlags) -split ',' | Where-Object { $_ -ne 'None' }
				$newflags = $TraceFlags
				$newflags = $oldflags + $newflags
				$newstartup.TraceFlags = ($oldFlags + $newflags | Sort-Object -Unique) -join ','
			}
			elseif ($TraceFlagsOverride) {
				$newstartup.TraceFlags = ''
			}
			else {
				$newstartup.TraceFlags = if ($currentstartup.TraceFlags -eq 'None') { }
				else { $currentstartup.TraceFlags -join ',' }
			}
			If ($newstartup.TraceFlags.Length -ne 0) {
				$ParameterString += (($newstartup.TraceFlags.split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
			}
		}
		
		$instance, $instancename = ($sqlinstance.Split('\'))
		Write-Message -Level Verbose -Message "Attempting to connect to $instancename on $instance"
		
		if ($instancename.Length -eq 0) { $instancename = "MSSQLSERVER" }
		
		$displayname = "SQL Server ($instancename)"
		
		if ($originalparamstring -eq "$ParameterString" -or "$originalparamstring;" -eq "$ParameterString") {
			Stop-Function -Message "New parameter string would be the same as the old parameter string. Nothing to do." -Target $ParameterString
			return
		}
		
		$Scriptblock = {
			$instance = $args[0]
			$displayname = $args[1]
			$ParameterString = $args[2]
			
			$wmisvc = $wmi.Services | Where-Object { $_.DisplayName -eq $displayname }
			$wmisvc.StartupParameters = $ParameterString
			$wmisvc.Alter()
			$wmisvc.Refresh()
			if ($wmisvc.StartupParameters -eq $ParameterString) {
				$true
			}
			else {
				$false
			}
		}
		
		if ($pscmdlet.ShouldProcess("Setting Sql Server start parameters on $sqlinstance to $ParameterString")) {
			try {
				if ($credential) {
					$response = Invoke-ManagedComputerCommand -Server $instance -Credential $credential -ScriptBlock $Scriptblock -ArgumentList $instance, $displayname, $ParameterString
					$output = Get-DbaStartupParameter -SqlInstance $sqlinstance -Credential $Credential
					Add-Member -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalparamstring
				}
				else {
					$response = Invoke-ManagedComputerCommand -Server $instance -ScriptBlock $Scriptblock -ArgumentList $instance, $displayname, $ParameterString
					$output = Get-DbaStartupParameter -SqlInstance $sqlinstance
					Add-Member -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalparamstring
				}
				
				$output
				
				Write-Message -Level Output -Message "Startup parameters changed on $sqlinstance. You must restart SQL Server for changes to take effect."
				}
			catch {
				Stop-Function -Message "Startup parameters failed to change on $sqlinstance. Failure reported: $_" -Target $_
			}
		}
	}
}
