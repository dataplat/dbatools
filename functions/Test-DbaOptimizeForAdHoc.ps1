Function Test-DbaOptimizeForAdHoc
{
<# 
.SYNOPSIS 
Displays information relating to SQL Server Optimize for AdHoc Workloads setting.  Works on SQL Server 2008-2016.

.DESCRIPTION 
When this option is set, plan cache size is further reduced for single-use adhoc OLTP workload.

More info: https://msdn.microsoft.com/en-us/library/cc645587.aspx
http://www.sqlservercentral.com/blogs/glennberry/2011/02/25/some-suggested-sql-server-2008-r2-instance-configuration-settings/

These are just general recommendations for SQL Server and are a good starting point for setting the "optimize for adhoc workloads" option.

.PARAMETER SqlInstance
Allows you to specify a comma separated list of servers to query.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.NOTES 
Author: Brandon Abshire, netnerds.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Test-DbaOptimizeAdHoc

.EXAMPLE   
Test-DbaOptimizeAdHoc -SqlInstance sql2008, sqlserver2012
Get Optimize for AdHoc Workloads setting for servers sql2008 and sqlserver2012 and also the recommended one.

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential
	)
	
	BEGIN
	{
        $notesAdHocZero = "Recommended configuration is 1"
		$notesAsRecommended = "Configuration is as recommended"
	}
	
	PROCESS
	{
		
		foreach ($servername in $SqlInstance)
		{
			Write-Verbose "Attempting to connect to $servername"
			try
			{
				$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $servername or access denied. Skipping."
				continue
			}
			
			if ($server.versionMajor -lt 10)
			{
				Write-Warning "This function does not support versions lower than SQL Server 2008 (v10). Skipping server $servername."
				
				Continue
			}
			
			#Get current configured value
            $optimizeAdHoc = $server.Configuration.OptimizeAdhocWorkloads.ConfigValue
			
			
			#Setting notes for optimize adhoc value
			if ($optimizeAdHoc -eq 1)
			{
				$notes = $notesAsRecommended
			}
			else
			{
				$notes = $notesAdHocZero
			}
			
			[pscustomobject]@{
				Instance = $server.Name
				CurrentOptimizeAdHoc = $optimizeAdHoc
        		RecommendedOptimizeAdHoc = 1
				Notes = $notes
			}
		}
	}
}
