<#  
.SYNOPSIS  
Get detailed information about detached SQL Server database files.

.DESCRIPTION
This script gathers the following information from detached database files: database name, SQL Server version (compatibility level), collation, and file structure. "Data files" and "Log file" report the structure of the data and log files as they were when the database was detached. "Database version" is the comptability level.
 
.PARAMETER Server
An online SQL Server is required to parse the information within the detached database file. Note that this script will not attach the file, it will simply use SQL Server to read its contents.
 
.PARAMETER MDF 
The path to the MDF file. This path must be readable by the SQL Server service account. Ideally, the MDF will be located on the SQL Server itself, or on a network share to which the SQL Server service account has access. 

.NOTES  
Author  : Chrissy LeMaire 
Requires:     PowerShell Version 3.0, SQL Server SMO
DateUpdated: 2015-Jan-22
Version: 1.0
 
.LINK
 https://gallery.technet.microsoft.com/scriptcenter/Get-Detached-SQL-Server-7ad8d4e7
 
.EXAMPLE    
.\Get-DetachedDBInfo.ps1 -Server sqlserver -MDF M:\Archive\mydb.mdf
 
#> 

#Requires -Version 3.0
[CmdletBinding(DefaultParameterSetName="Default")]

Param(
	[parameter(Mandatory = $true)]
	[string]$Server,
	[parameter(Mandatory = $true)]
	[string]$MDF
	)

BEGIN {
	Function Get-DetachedDBInfo {
		[CmdletBinding()]
		param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$server,
			[string]$mdf	
		)

		$datafiles = New-Object System.Collections.Specialized.StringCollection
		$logfiles = New-Object System.Collections.Specialized.StringCollection
		
		try {
			$detachedDatabaseInfo = $server.DetachedDatabaseInfo($mdf)
			$dbname = ( $detachedDatabaseInfo | Where { $_.Property -eq "Database name" }).Value
			$dbversion = ($detachedDatabaseInfo | Where { $_.Property -eq "Database version" }).Value
			$collationid = ($detachedDatabaseInfo | Where { $_.Property -eq "Collation" }).Value
		} catch { throw "$($server.name) cannot read the file $($MDF). Does service account $($server.ServiceAccount) have accesss to that path?" }

		switch ($dbversion) {
			782 {$dbversion = "SQL Server 2014"}
			706 {$dbversion = "SQL Server 2012"}
			684 {$dbversion = "SQL Server 2012 CTP1"}
			661 {$dbversion = "SQL Server 2008 R2"}
			660 {$dbversion = "SQL Server 2008 R2"}
			655 {$dbversion = "SQL Server 2008 SP2+"}
			612 {$dbversion = "SQL Server 2005"}
			611 {$dbversion = "SQL Server 2005"}
			539 {$dbversion = "SQL Server 2000"}
			515 {$dbversion = "SQL Server 7.0"}
			408 {$dbversion = "SQL Server 6.5"}
		}
		
		$collationsql = "SELECT name FROM fn_helpcollations() where collationproperty(name, N'COLLATIONID')  = $collationid"
		try {
			$dataset = $server.databases['master'].ExecuteWithResults($collationsql)
			$collation = "$($dataset.Tables[0].Rows[0].Item(0))"
		} catch { $collation = $collationid }
		
		if ($collation.length -eq 0) { $collation = $collationid }
		
		try {
			foreach    ($file in $server.EnumDetachedDatabaseFiles($mdf)) {
				$datafiles +=$file
			}
			 
			foreach ($file in $server.EnumDetachedLogFiles($mdf)) {
				$logfiles +=$file
			}
		} catch { throw "$($server.name) enumerate database or log structure information for $($MDF)" }
			
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

PROCESS {
	[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO")

	$smoserver = New-Object Microsoft.SqlServer.Management.Smo.Server $server
	try { $smoserver.ConnectionContext.Connect() } catch { throw "Can't connect to SQL Server." }
	
	# Get-DetachedDBInfo returns a custom object. Data file and log files are a string collection.
	$mdfinfo = Get-DetachedDBInfo $smoserver $mdf
	
	Write-Host "The following information was gathered about the detatched database:" -ForegroundColor Green
	$mdfinfo
	
}

END {
	$smoserver.ConnectionContext.Disconnect()
	}