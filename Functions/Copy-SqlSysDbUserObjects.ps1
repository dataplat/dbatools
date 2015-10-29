Function Copy-SqlSysDbUserObjects  { 
<#
.SYNOPSIS
Imports *all* user objects found in source SQL Server's master, msdb and model databases to the destination.
This is useful because many DbA's store backup/maintenance procs/tables/triggers/etc (among other things) in master or msdb.

It is also useful for migrating objects within the model database.

.EXAMPLE
Copy-SqlSysDbUserObjects $sourceserver $destserver

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

#>
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[object]$source,
	
	[Parameter(Mandatory = $true)]
	[ValidateNotNullOrEmpty()]
	[object]$destination,
	
	[System.Management.Automation.PSCredential]$SourceSqlCredential,
	[System.Management.Automation.PSCredential]$DestinationSqlCredential
)
	
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name
	
	if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
	
	$systemdbs = "master","model","msdb"
	
	foreach ($systemdb in $systemdbs) {
		$sysdb = $sourceserver.databases[$systemdb]
		$transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $sysdb
		$transfer.CopyAllObjects = $false
		$transfer.CopyAllDatabaseTriggers = $true
		$transfer.CopyAllTables = $true
		$transfer.CopyAllViews = $true
		$transfer.CopyAllStoredProcedures = $true
		$transfer.CopyAllUserDefinedAggregates = $true
		$transfer.CopyAllUserDefinedDataTypes = $true
		$transfer.CopyAllUserDefinedTableTypes = $true
		$transfer.CopyAllUserDefinedTypes = $true
		$transfer.PreserveDbo = $true
		$transfer.Options.AllowSystemObjects = $false
		$transfer.Options.ContinueScriptingOnError = $true
		Write-Output "Copying from $systemdb"
		try { 
			$sqlQueries = $transfer.scriptTransfer()
			foreach ($query in $sqlQueries) {
				try { $destserver.Databases[$systemdb].ExecuteNonQuery($query)} catch {}  # This usually occurs if there are existing objects in destination
			}
		} catch { Write-Output "Exception caught."}
	}
	Write-Output "Migrating user objects in system databases finished"
}
