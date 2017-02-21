Function Copy-SqlAlert
{
<#
.SYNOPSIS 
Copy-SqlAlert migrates alerts from one SQL Server to another. 

.DESCRIPTION
By default, all alerts are copied. The -Alerts parameter is autopopulated for command-line completion and can be used to copy only specific alerts.

If the alert already exists on the destination, it will be skipped unless -Force is used.  

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	

To connect as a different Windows user, run PowerShell as that user.

.PARAMETER IncludeDefaults
Copy SQL Agent defaults such as FailSafeEmailAddress, ForwardingServer, and PagerSubjectTemplate.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlAlert

.EXAMPLE   
Copy-SqlAlert -Source sqlserver2014a -Destination sqlcluster

Copies all alerts from sqlserver2014a to sqlcluster, using Windows credentials. If alerts with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlAlert -Source sqlserver2014a -Destination sqlcluster -Alert PSAlert -SourceSqlCredential $cred -Force

Copies a single alert, the PSAlert alert from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a alert with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-SqlAlert -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$IncludeDefaults,
		[switch]$Force
	)
	DynamicParam { if ($source) { return (Get-ParamSqlAlerts -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		$alerts = $psboundparameters.Alerts
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
	}
	PROCESS
	{
		
		$serveralerts = $sourceserver.JobServer.Alerts
		$destalerts = $destserver.JobServer.Alerts
		
		if ($IncludeDefaults -eq $true)
		{
			If ($Pscmdlet.ShouldProcess($destination, "Copying Alert Defaults"))
			{
				try
				{
					Write-Output "Copying Alert Defaults"
					$sql = $sourceserver.JobServer.AlertSystem.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Verbose $sql
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
		
		foreach ($alert in $serveralerts)
		{
			$alertname = $alert.name
			if ($alerts.count -gt 0 -and $alerts -notcontains $alertname) { continue }
			
			if ($destalerts.name -contains $alert.name)
			{
				if ($force -eq $false)
				{
					Write-Warning "Alert $alertname exists at destination. Use -Force to drop and migrate."
					continue
				}
				
				If ($Pscmdlet.ShouldProcess($destination, "Dropping alert $alertname and recreating"))
				{
					try
					{
						Write-Verbose "Dropping Alert $alertname on $destserver"
						#$destserver.JobServer.Alerts[$alertname].Drop()
						
						$sql = "EXEC msdb.dbo.sp_delete_alert @name = N'$($alert.name)';"
						Write-Verbose $sql
						$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
					}
					catch
					{
						Write-Exception $_
						continue
					}
				}
			}
			# job is created here.
			If ($Pscmdlet.ShouldProcess($destination, "Creating Alert $alertname"))
			{
				try
				{
					Write-Output "Copying Alert $alertname"
					$sql = $alert.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					$alertsql = $sql -replace "@job_id=N'........-....-....-....-............", "@job_id=N'00000000-0000-0000-0000-000000000000"
					Write-Verbose $sql
					$destserver.ConnectionContext.ExecuteNonQuery($alertsql) | Out-Null
				}
				catch
				{
					Write-Exception $_
				}
			}
			
			$destserver.JobServer.Alerts.Refresh()
			$destserver.JobServer.Jobs.Refresh()
			
			# Super workaround but it works
			if ($alert.JobId -ne '00000000-0000-0000-0000-000000000000')
			{
				
				If ($Pscmdlet.ShouldProcess($destination, "Adding $alertname to $jobname"))
				{
					try
					{
						Write-Output  "Adding $alertname to $jobname"
						$newjob = $destserver.JobServer.Jobs[$jobname]
						$newjobid = ($newjob.JobId) -replace " ", ""
						$alertsql = $alertsql -replace '00000000-0000-0000-0000-000000000000', $newjobid
						$alertsql = $alertsql -replace 'sp_add_alert', 'sp_update_alert'
						Write-Verbose $sql
						$destserver.ConnectionContext.ExecuteNonQuery($alertsql) | Out-Null
					}
					catch
					{
						Write-Exception $_
					}
				}
			}
			
			
			$newalert = $destserver.JobServer.Alerts[$alertname]
			$notifications = $alert.EnumNotifications()
			$newnotifications = $newalert.EnumNotifications()
			$job = $alert.JobId
			$jobname = $alert.JobName
			
			If ($Pscmdlet.ShouldProcess($destination, "Moving Notifications $alertname"))
			{
				try
				{
					foreach ($notify in $notifications)
					# cant add them this way, we need to modify the existing one or give all options that are supported.
					{
						$nm = @()
						if ($notify.UseNetSend -eq $true)
						{
							write-verbose "Adding net send"
							$nm += "NetSend"
						}
						
						if ($notify.UseEmail -eq $true)
						{
							write-verbose "Adding email"
							$nm += "NotifyEmail"
						}
						
						if ($notify.UsePager -eq $true)
						{
							write-verbose "Adding pager"
							$nm += "Pager"
						}
						$nml = $nm -join ", "
						
						$newalert.AddNotification($notify.OperatorName, [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]$nml) # concat the notify methods together       
					}
				}
				catch
				{
					$e = $_.Exception
					$line = $_.InvocationInfo.ScriptLineNumber
					$msg = $e.Message
					
					if ($e -like '*The specified @operator_name (''*'') does not exist*')
					{
						Write-Warning "One or more operators for this alert are not configured and will not be added to this alert."
						Write-Warning "Please run Copy-SqlOperator if you would like to move operators to destination server."
					}
					else
					{
						Write-Error "caught exception: $e at $line : $msg"
					}
				}
			}
			
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Alert migration finished" }
	}
}