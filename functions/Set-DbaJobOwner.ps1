function Set-DbaJobOwner
{
<#
.SYNOPSIS
Sets SQL Agent job owners with a desired login if jobs do not match that owner.

.DESCRIPTION
This function will alter SQL Agent Job ownership to match a specified login if their
current owner does not match the target login. By default, the target login will
be 'sa', but the fuction will allow the user to specify a different login for 
ownership. The user can also apply this to all jobs or only to a select list
of jobs (passed as either a comma separated list or a string array).
	
Best practice reference: http://sqlmag.com/blog/sql-server-tip-assign-ownership-jobs-sysadmin-account
	
.NOTES 
Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, currend Windows login will be used.

.PARAMETER Jobs
Auto-populated list of Jobs to apply changes to. Will accept a comma separated list or a string array.

.PARAMETER Exclude
Jobs to exclude
	
.PARAMETER TargetLogin
Specific login that you wish to check for ownership. This defaults to 'sa' or the sysadmin name if sa was renamed.

.LINK
https://dbatools.io/Set-DbaJobOwner

.EXAMPLE
Set-DbaJobOwner -SqlServer localhost

Sets SQL Agent Job owner to sa on all jobs where the owner does not match sa.

.EXAMPLE
Set-DbaJobOwner -SqlServer localhost -TargetLogin DOMAIN\account

Sets SQL Agent Job owner to sa on all jobs where the owner does not match 'DOMAIN\account'. Note
that TargetLogin must be a valid security principal that exists on the target server.

.EXAMPLE
Set-DbaJobOwner -SqlServer localhost -Job job1, job2

Sets SQL Agent Job owner to 'sa' on the job1 and job2 jobs if their current owner does not match 'sa'.

.EXAMPLE
'sqlserver','sql2016' | Set-DbaJobOwner 

Sets SQL Agent Job owner to sa on all jobs where the owner does not match sa on both sqlserver and sql2016.
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[object]$SqlCredential,
		[string]$TargetLogin
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlJobs -SqlServer $SqlServer[0] -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		$jobs = $psboundparameters.Jobs
		$exclude = $psboundparameters.Exclude
	}
	
	PROCESS
	{
		foreach ($servername in $sqlserver)
		{
			#connect to the instance
			Write-Verbose "Connecting to $servername"
			$server = Connect-SqlServer $servername -SqlCredential $SqlCredential
			
			# dynamic sa name for orgs who have changed their sa name
			if ($psboundparameters.TargetLogin.length -eq 0)
			{
				$TargetLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
			}
			
			#Validate login
			if (($server.Logins.Name) -notcontains $TargetLogin)
			{
				if ($sqlserver.count -eq 1)
				{
					throw "Invalid login: $TargetLogin"
				}
				else
				{
					Write-Warning "$TargetLogin is not a valid login on $servername. Moving on."
					Continue
				}
			}
			
			if ($server.logins[$TargetLogin].LoginType -eq 'WindowsGroup')
			{
				throw "$TargetLogin is a Windows Group and can not be a job owner."
			}
			
			#Get database list. If value for -Jobs is passed, massage to make it a string array.
			#Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
			Write-Verbose "Gathering jobs to update"
			
			if ($Jobs.Length -gt 0)
			{
				$jobcollection = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $TargetLogin -and $jobs -contains $_.Name }
			}
			else
			{
				$jobcollection = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $TargetLogin }
			}
			
			if ($Exclude.Length -gt 0)
			{
				$jobcollection = $jobcollection | Where-Object { $Exclude -notcontains $_.Name }
			}
			
			Write-Verbose "Updating $($jobcollection.Count) job(s)."
			foreach ($j in $jobcollection)
			{
				$jobname = $j.name
				
				If ($PSCmdlet.ShouldProcess($servername, "Setting job owner for $jobname to $TargetLogin"))
				{
					try
					{
						Write-Output "Setting job owner for $jobname to $TargetLogin on $servername"
						#Set job owner to $TargetLogin (default 'sa')
						$j.OwnerLoginName = $TargetLogin
						$j.Alter()
					}
					catch
					{
						# write-exception writes the full exception to file
						Write-Exception $_
						throw $_
					}
				}
			}
		}
	}
	
	END
	{
		if ($jobcollection.count -eq 0)
		{
			Write-Output "Lookin' good! Nothing to do."
		}
		
		Write-Verbose "Closing connection"
		$server.ConnectionContext.Disconnect()
	}
}