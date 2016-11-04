FUNCTION Find-DbaAgentJob
{
<#
.SYNOPSIS 
Find-DbaAgentJob finds agent job/s that fit certain search filters.

.DESCRIPTION
This command filters SQL Agent jobs giving the DBA a list of jobs that may need attention or could possibly be options for removal. 
	
.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER LastUsed
Find all jobs that havent ran in the INT number of previous day(s)

.PARAMETER Disabled
Find all jobs that are disabled
	
.PARAMETER NoSchedule
Find all jobs with schedule set to it
	
.PARAMETER EmailNotification
Find all jobs without email notification configured

.PARAMETER Filter
Allows you to enter an array of agent job names to ignore 

.PARAMETER Detailed
Returns a more detailed output showing why each job has been reported
	
.NOTES 
Author: Stephen Bennett: https://sqlnotesfromtheunderground.wordpress.com/
Requires: sysadmin access on SQL Servers
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Find-DbaAgentJob

.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01 -LastUsed 10 
Returns all agent job(s) that have not ran in 10 days

.EXAMPLE 
Find-DBAAgentJob -SQLServer Dev01 -Disabled -EmailNotification -NoSchedule -Detailed
Returns all agent job(s) that are either disabled, have no email notification or dont have a schedule. returned with detail

.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01 -LastUsed 10 -Filter "Yearly - RollUp Workload", "SMS - Notification" 
Returns all agent jobs that havent ran in the last 10 ignoring jobs "Yearly - RollUp Workload" and "SMS - Notification" 
#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[int]$LastUsed,
        [switch]$Disabled,
        [switch]$NoSchedule,
        [switch]$EmailNotification,
        [string[]]$Filter,
        [switch]$Detailed
	)
	BEGIN
	    {
            $output = @()
	    }
	PROCESS
	    {
		    FOREACH ($instance in $SqlServer)
		    {
                Write-Verbose "Running Scan on: $instance"

                TRY
			    {
				    $server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			    }
			    CATCH
			    {
				    Write-Verbose "Failed to connect to: $instance"
				    continue
			    }
                
                
                IF ($Filter)
                    {
                        Write-Verbose "Applying filter/s"
                        $jobs | Where-Object {$Filter -notcontains $_.name}
                    }
                ELSE
                    {
                        $jobs = $server.JobServer.jobs
                    }
                IF ($LastUsed)
                    {
                        $Since = $LastUsed * -1
                        $SinceDate = (Get-date).AddDays($Since)
                        Write-Verbose "Finding jobs not ran in last $Since days"
                        $output = $jobs | Where-Object { $_.LastRunDate -le $SinceDate }
                    }
                IF ($Disabled -eq $true)
                    {
                        Write-Verbose "Finding job/s that are disabled"
                        $output += $jobs | Where-Object { $_.IsEnabled -eq $false }
                    }
                IF ($NoSchedule -eq $true)
                    {
                        Write-Verbose "Finding job/s that have no schedule defined"
                        $output += $jobs | Where-Object { $_.HasSchedule -eq $false }
                    }
                IF ($EmailNotification -eq $true)
                    {
                        Write-Verbose "Finding job/s that have no email operator defined"
                        $output += $jobs | Where-Object {$_.OperatorToEmail -eq "" }
                    }
            }
        }
    END
        {
            IF ($Detailed -eq $true)
		        {
                    return ($output | Select-Object name, LastRunDate, IsEnabled, HasSchedule, OperatorToEmail -Unique)
		        }
		    ELSE
		        {
			        return ($output | Select-Object name -Unique)    
		        }
        }           
}
