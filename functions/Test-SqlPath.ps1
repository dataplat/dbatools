Function Test-SqlPath
{
<# 
.SYNOPSIS
Tests if file or directory exists from the perspective of the SQL Server service account

.DESCRIPTION
Uses master.dbo.xp_fileexist to determine if a file or directory exists
	
.PARAMETER SqlServer
The SQL Server you want to run the test on.
	
.PARAMETER Path
The Path to tests. Can be a file or directory.
	
.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: Admin access to server (not SQL Services), 
Remoting must be enabled and accessible if $sqlserver is not local

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
https://dbatools.io/Test-SqlPath 

.EXAMPLE   
Test-SqlPath -SqlServer sqlcluster -Path L:\MSAS12.MSSQLSERVER\OLAP

Tests whether the service account running the "sqlcluster" SQL Server isntance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using Windows credentials. 
	
.EXAMPLE  
$credential = Get-Credential
Test-SqlPath -SqlServer sqlcluster -SqlCredential $credential -Path L:\MSAS12.MSSQLSERVER\OLAP
	
Tests whether the service account running the "sqlcluster" SQL Server isntance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using SQL authentication. 
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$sql = "EXEC master.dbo.xp_fileexist '$path'"
	$fileexist = $server.ConnectionContext.ExecuteWithResults($sql)
	
	if ($fileexist.tables.rows['File Exists'] -eq $true -or $fileexist.tables.rows['File is a Directory'] -eq $true)
	{
		return $true
	}
	else
	{
		return $false
	}
}