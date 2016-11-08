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

.PARAMETER Exclude
Allows you to enter an array of agent job names to ignore 

.PARAMETER Name
Filter agent jobs to only the names you list

.PARAMETER Category 
Filter based on Agent Job Categories

.PARAMETER Detailed
Returns a more detailed output showing why each job has been reported

.PARAMETER CombineFilters
Returns only job/s that meet all critera 	

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
Find-DbaAgentJob -SQLServer Dev01 -LastUsed 10 -Exclude "Yearly - RollUp Workload", "SMS - Notification" 
Returns all agent jobs that havent ran in the last 10 ignoring jobs "Yearly - RollUp Workload" and "SMS - Notification" 

.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01 -LastUsed 10 -Exclude "Yearly - RollUp Workload", "SMS - Notification" 
Returns all agent jobs that havent ran in the last 10 ignoring jobs "Yearly - RollUp Workload" and "SMS - Notification" 

.EXAMPLE
Find-DbaAgentJon -SQLServer Dev01 -LastUsed 10 -Disabled -CombineFilters
Returns any job/s on Dev01 that are BOTH disabled and have not been ran in the last 10 days 

.EXAMPLE 
Find-DbaAgentJob -SqlServer Dev01 -Category "REPL-Distribution", "REPL-Snapshot" -Detailed | ft -AutoSize -Wrap 
Returns all job/s on Dev01 that are in either category "REPL-Distribution" or "REPL-Snapshot" with detailed output

.EXAMPLE 
Get-SqlRegisteredServerName -SqlServer CMSServer -Group Production | Find-DbaAgentJob -Disabled -NoSchedule -Detailed | ft -AutoSize -Wrap
Queries CMS server to return all SQL instances in the Production folder and then list out all agent jobs that have either been disabled or have no schedule. 

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
        [string[]]$Category,
        [string[]]$Exclude,
        [string[]]$Name,
        [switch]$CombineFilters,
        [switch]$Detailed
	)
	BEGIN
	    {
            $output = @()
	    }
	PROCESS
	    {
		    FOREACH ($servername in $SqlServer)
		    {
                Write-Verbose "Running Scan on: $servername"

                TRY
			        {
				        $server = Connect-SqlServer -SqlServer $servername -SqlCredential $sqlcredential
			        }
			    CATCH
			        {
				        Write-Verbose "Failed to connect to: $servername"
				        continue
			        }
                IF ($CombineFilters)
                    {
                        $filter = 0
                        $DynString = '$output = $server.JobServer.jobs'
                        
                        IF ($Exclude)
                            {
                                $filter = 1
                                Write-Verbose "Excluding job/s based on Exclude"
                                $DynString = '$output = $jobs | Where-Object { $Exclude -notcontains $_.name '
                            }
                        ELSEIF ($name)
                            {
                               $filter = 1
                               $DynString = '$output = $jobs | Where-Object { $name -eq $_.name '
                            }
                        
                        IF ($LastUsed)
                            {
                                $Since = $LastUsed * -1
                                $SinceDate = (Get-date).AddDays($Since)
                                Write-Verbose "Finding job/s not ran in last $Since days"
                                $DynString += ' | Where-Object { $_.LastRunDate -le $SinceDate '
                                $filter = 1
                            }
                        IF ($Disabled -eq $true)
                            {
                                Write-Verbose "Finding job/s that are disabled"
                                IF ($filter -eq 1)
                                    {
                                        $DynString += '-and $_.IsEnabled -eq $false '
                                    }
                                ELSEIF ($filter -eq 0)
                                    {
                                        $DynString += ' | Where-Object { $_.IsEnabled -eq $false '
                                        $filter = 1
                                    }
                            }
                        IF ($NoSchedule -eq $true)
                            {
                                Write-Verbose "Finding job/s that have no schedule defined"
                                IF ($filter -eq 0)
                                    {
                                        $DynString += ' | Where-Object { $_.HasSchedule -eq $false '
                                        $filter = 1
                                    }
                                ELSEIF ($filter -eq 1)
                                    {
                                        $DynString += '-and $_.HasSchedule -eq $false '
                                    }
                            }
                        IF ($EmailNotification -eq $true)
                            {
                                Write-Verbose "Finding job/s that have no email operator defined"
                                IF ($filter -eq 0)
                                    {
                                        $DynString += ' | Where-Object { $_.OperatorToEmail -eq "" '
                                        $filter = 1
                                    }
                                ELSEIF ($filter -eq 1)
                                    {
                                        $DynString += '-and $_.OperatorToEmail -eq "" '
                                    }
                            }
                        IF ($Category)
                            {
                                Write-Verbose "Finding job/s that are in category/s defined"
                                IF ($filter -eq 0)
                                    {
                                        $DynString += ' | Where-Object { $Category -contains $_.Category '
                                    }
                                ELSEIF ($filter -eq 1)
                                    {
                                        $DynString += '-and $Category -contains $_.Category '
                                    }


                            }

                        IF (!($DynString -eq '$output = $server.JobServer.jobs'))
                            {
                            $DynString += ' }'
                            }
         

                        Write-Verbose "Dynamic String output:  $DynString"
                        Invoke-Expression $DynString
                    }
                ELSE # $CombineFilters
                    {
                        $jobs = $server.JobServer.jobs
                        
                        IF ($Exclude)
                            {
                                Write-Verbose "Excluding job/s based on Exclude"
                                $jobs = $jobs | Where-Object { $Exclude -notcontains $_.name }
                            }
                        ELSEIF ($name)
                            {
                                $jobs = $jobs | Where-Object { $name -eq $_.name } 
                            }

                        IF ($LastUsed)
                            {
                                $Since = $LastUsed * -1
                                $SinceDate = (Get-date).AddDays($Since)
                                Write-Verbose "Finding job/s not ran in last $Since days"
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
                                $output += $jobs | Where-Object { $_.OperatorToEmail -eq "" }
                            }
                        IF ($Category)
                            {
                                Write-Verbose "Finding job/s that have no email operator defined"
                                $output += $jobs | Where-Object { $Category -contains $_.Category }
                            }

                        IF (!($output))
                            {
                                $output = $jobs
                            }
                    }
            }
        }
    END
        {
            IF ($Detailed -eq $true)
		        {
                    return ($output | Select-Object @{Name="ServerName";Expression={ $_.Parent.name }}, name, LastRunDate, IsEnabled, HasSchedule, OperatorToEmail, Category -Unique)
		        }
		    ELSE
		        {
			        return ($output | Select-Object @{Name="ServerName";Expression={ $_.Parent.name }}, name -Unique)    
		        }
        }           
}
