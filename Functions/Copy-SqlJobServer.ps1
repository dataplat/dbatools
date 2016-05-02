Function Copy-SqlJobServer      {
<#
.SYNOPSIS
Copies *all* ProxyAccounts, JobSchedule, SharedSchedules, AlertSystem, JobCategories, 
OperatorCategories AlertCategories, Alerts, TargetServerGroups, TargetServers, 
Operators, Jobs, Mail and general SQL Agent settings from one SQL Server Agent 
to another. $sourceserver and $destserver are SMO server objects. 

Ignores -force: does not drop and recreate.

.DESCRIPTION
This function could use some refining, as *all* job objects are copied. 

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source Sql Server. You must have sysadmin access and server version must be > Sql Server 7.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be > Sql Server 7.

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

.PARAMETER CsvLog
Outputs an ordered CSV log of migration successes, failures and skips.

.PARAMETER DisableJobsOnDestination
When this flag is set, copy all jobs as Enabled=0

.NOTES 
Author  : Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (http://git.io/b3oo, clemaire@gmail.com)
Copyright (C) 2105 Chrissy LeMaire

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


.EXAMPLE   
Copy-SqlJobServer -Source sqlserver2014a -Destination sqlcluster

Copies all job server objects from sqlserver2014a to sqlcluster, using Windows credentials. If job objects with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlJobServer -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

Copies all job objects from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster.

.EXAMPLE   
Copy-SqlServerTrigger -Source sqlserver2014a -Destination sqlcluster -WhatIf

Shows what would happen if the command were executed.
#>

[cmdletbinding(SupportsShouldProcess = $true)] 
param(
	[parameter(Mandatory = $true)]
	[object]$Source,
	[parameter(Mandatory = $true)]
	[object]$Destination,
	[System.Management.Automation.PSCredential]$SourceSqlCredential,
	[System.Management.Automation.PSCredential]$DestinationSqlCredential,
	[Switch]$CsvLog,
	[Switch]$DisableJobsOnDestination
    
)
	
PROCESS {
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
	
	Invoke-SmoCheck -SqlServer $sourceserver
	Invoke-SmoCheck -SqlServer $destserver
	
	$source = $sourceserver.name
	$destination = $destserver.name	
	
	if (!(Test-SqlAgent $sourceserver)) { Write-Error "SQL Agent not running on $source. Halting job import."; return }
	if (!(Test-SqlAgent $destserver)) { Write-Error "SQL Agent not running on $destination. Halting job import."; return }
		
	$sourceagent = $sourceserver.jobserver
	$migratedjob = @{}; $skippedjob = @{}
	
	$jobobjects = "ProxyAccounts","JobSchedule","SharedSchedules","AlertSystem","JobCategories","OperatorCategories"
	$jobobjects += "AlertCategories","Alerts","TargetServerGroups","TargetServers","Operators", "Jobs", "Mail"
	
	$errorcount = 0
	foreach ($jobobject in $jobobjects) {
		foreach($agent in $sourceagent.($jobobject)) {		
		$agentname = $agent.name
		If ($Pscmdlet.ShouldProcess($destination,"Adding $jobobject $agentname")) {
				try {
                if($DisableJobsOnDestination -and ($jobobject -eq "Jobs"))
                {
                    $agent.IsEnabled = $False
                }
				$sql = $agent.script()	
				$sql = $sql -replace [regex]::Escape("@server=N'$source'"), "@server=N'$destination'"
				$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
				$migratedjob["$jobobject $agentname"] = "Successfully added"
				Write-Output "$agentname successfully migrated "
				} 
				catch {
					if ($_.Exception -like '*duplicate*' -or $_.Exception -like '*already exists*') {
						Write-Output "$agentname exists at destination"
						$skippedjob.Add("$jobobject $agentname","Skipped. $agentname exists on $destination.") }
					else {
                        $skippedjob["$jobobject $agentname"] = $_.Exception.InnerException.InnerException.Message
                        Write-Error "$jobobject : $agentname : $($_.Exception.InnerException.InnerException.Message)" 
                    }
				}
			}
		}
	 }
	
	if ($csvlog) {
		$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
		$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
		$migratedjob.GetEnumerator() | Sort-Object | Select Name, Value | Export-Csv -Path "$csvfilename-jobs.csv" -NoTypeInformation
		$skippedjob.GetEnumerator() | Sort-Object | Select Name, Value | Export-Csv -Append -Path "$csvfilename-jobs.csv" -NoTypeInformation
	}
}

END {
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	If ($Pscmdlet.ShouldProcess("console","Showing finished message")) { Write-Output "Job server migration finished" }
}
}
