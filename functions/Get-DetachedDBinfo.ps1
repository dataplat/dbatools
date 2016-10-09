Function Get-DetachedDbInfo
{
<#  
.SYNOPSIS  
Get detailed information about detached SQL Server database files.

.DESCRIPTION
This script gathers the following information from detached database files: database name, SQL Server version (compatibility level), collation, and file structure. "Data files" and "Log file" report the structure of the data and log files as they were when the database was detached. "Database version" is the comptability level.
 
.PARAMETER SqlServer
An online SQL Server is required to parse the information within the detached database file. Note that this script will not attach the file, it will simply use SQL Server to read its contents.
 
.PARAMETER MDF 
The path to the MDF file. This path must be readable by the SQL Server service account. Ideally, the MDF will be located on the SQL Server itself, or on a network share to which the SQL Server service account has access. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
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
https://dbatools.io/Get-DetachedDbInfo
 
.EXAMPLE    
Get-DetachedDbInfo -SqlServer sqlserver -SqlCredential $SqlCredential -MDF M:\Archive\mydb.mdf
 #>	
	
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[string]$SqlServer,
		[parameter(Mandatory = $true)]
		[string]$MDF,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	BEGIN
	{
		Function Get-MdfFileInfo
		{
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[Alias("ServerInstance","SqlInstance")]
				[object]$SqlServer,
				[string]$mdf,
				[System.Management.Automation.PSCredential]$SqlCredential
			)
			
			$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
			
			$datafiles = New-Object System.Collections.Specialized.StringCollection
			$logfiles = New-Object System.Collections.Specialized.StringCollection
			
			try
			{
				$detachedDatabaseInfo = $SqlServer.DetachedDatabaseInfo($mdf)
				$dbname = ($detachedDatabaseInfo | Where { $_.Property -eq "Database name" }).Value
				$dbversion = ($detachedDatabaseInfo | Where { $_.Property -eq "Database version" }).Value
				$collationid = ($detachedDatabaseInfo | Where { $_.Property -eq "Collation" }).Value
			}
			catch { throw "$($server.name) cannot read the file $($MDF). Does service account $($SqlServer.ServiceAccount) have accesss to that path and is the database detached?" }
			
			switch ($dbversion)
			{
				829 { $dbversion = "SQL Server 2016" }
				782 { $dbversion = "SQL Server 2014" }
				706 { $dbversion = "SQL Server 2012" }
				684 { $dbversion = "SQL Server 2012 CTP1" }
				661 { $dbversion = "SQL Server 2008 R2" }
				660 { $dbversion = "SQL Server 2008 R2" }
				655 { $dbversion = "SQL Server 2008 SP2+" }
				612 { $dbversion = "SQL Server 2005" }
				611 { $dbversion = "SQL Server 2005" }
				539 { $dbversion = "SQL Server 2000" }
				515 { $dbversion = "SQL Server 7.0" }
				408 { $dbversion = "SQL Server 6.5" }
				default { $dbversion = "Unknown ($dbversion)" }
			}
			
			$collationsql = "SELECT name FROM fn_helpcollations() where collationproperty(name, N'COLLATIONID')  = $collationid"
			try
			{
				$dataset = $SqlServer.databases['master'].ExecuteWithResults($collationsql)
				$collation = "$($dataset.Tables[0].Rows[0].Item(0))"
			}
			catch { $collation = $collationid }
			
			if ($collation.length -eq 0) { $collation = $collationid }
			
			try
			{
				foreach ($file in $SqlServer.EnumDetachedDatabaseFiles($mdf))
				{
					$datafiles += $file
				}
				
				foreach ($file in $SqlServer.EnumDetachedLogFiles($mdf))
				{
					$logfiles += $file
				}
			}
			catch { throw "$($SqlServer.name) enumerate database or log structure information for $($MDF)" }
			
			$mdfinfo = New-Object PSObject -Property @{
				"Database Name" = $dbname
				"Database Version" = $dbversion
				"Database Collation" = $collation
				"Data files" = $datafiles
				"Log files" = $logfiles
			}
			
			return $mdfinfo
		}
	}
	
	PROCESS
	{
		
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		
		# Get-DetachedDbInfo returns a custom object. Data file and log files are a string collection.
		$mdfinfo = Get-MdfFileInfo $server $mdf
		
		Write-Output "The following information was gathered about the detatched database:"
		Write-Output $mdfinfo
		
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}