Function Show-SqlWhoIsActive
{
<#
.SYNOPSIS
Output results of Adam Machanic's sp_WhoIsActive to a GridView (default) or DataTable, and installs it if necessary.

.DESCRIPTION
GridView is good for analysis while DataTable is good for SqlBulkCopy uploads to keep track
	
Initially, there will be a simple output, but eventually, we plan to support passing params and specifying columns.
	
This script was built with Adam's permission. To read more about sp_WhoIsActive, please visit:
	
Updates: http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx
"Beta" Builds: http://sqlblog.com/files/folders/beta/tags/who+is+active/default.aspx
	
Also, consider donating to Adam if you find this stored procedure helpful! http://tinyurl.com/WhoIsActiveDonate
	
.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER Database
The database where sp_WhoIsActive is installed. Defaults to master. If the sp_WhoIsActive is not installed, it will install it for you.
	
.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.NOTES 
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
https://dbatools.io/Show-SqlWhoIsActive

.EXAMPLE
Show-SqlWhoIsActive -SqlServer sqlserver2014a

More text coming soon
	
.EXAMPLE   
Show-SqlWhoIsActive -SqlServer sqlserver2014a -SqlCredential $credential

More text coming soon
#>
	
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[ValidateSet('Datatable', 'GridView')]
		#PsCustomObject needed? What else?
		[string]$OutputAs = 'GridView'
	)
	
	DynamicParam { if ($SqlServer) { return (Get-ParamSqlDatabase -SqlServer $SqlServer -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		function Install-SpWhoisActive
		{
			if ($database.length -eq 0)
			{
				$database = Show-SqlDatabaseList -SqlServer $sourceserver -Title "Install sp_WhoisActive" -Header "Select a database. The original script installs it to master by default." -DefaultDb "master"
				
				if ($database.length -eq 0)
				{
					throw "You must select a database to install the procedure"
				}
			}
			
			$parentPath = Split-Path -parent $PSScriptRoot
			$sql = [IO.File]::ReadAllText("$parentPath\sql\sp_WhoIsActive.sql")
			$sql = $sql -replace 'USE master', ''
			$batches = $sql -split "GO\r\n"
			
			foreach ($batch in $batches)
			{
				try
				{
					
					$null = $sourceserver.databases[$database].ExecuteNonQuery($batch)
					
				}
				catch
				{
					Write-Exception $_
					throw "Can't install stored procedure. See exception text for details."
				}
			}
			
			return $database
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		$source = $sourceserver.DomainInstanceName
		
		if ($sourceserver.VersionMajor -lt 9)
		{
			throw "sp_WhoIsActive is only supported in SQL Server 2005 and above"
		}
		
		$database = $psboundparameters.Database
	}
	
	PROCESS
	{
		# Will build more on this later and do some parameterization
		$sql = "dbo.sp_WhoIsActive"
		
		try
		{
			if ($database.length -eq 0)
			{
				$datatable = $sourceserver.databases["master"].ExecuteWithResults($sql)
			}
			else
			{
				$datatable = $sourceserver.databases[$database].ExecuteWithResults($sql)
			}
		}
		catch
		{
			Write-Output "Procedure not found, installing."
			$database = Install-SpWhoisActive
			try
			{
				$datatable = $sourceserver.databases[$database].ExecuteWithResults($sql)
			}
			catch
			{
				Write-Exception $_
				throw "Cannot execute procedure."
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		
		if ($datatable.Tables.Rows.Count -eq 0)
		{
			Write-Output "0 results returned"
			return
		}
		
		if ($OutputAs -eq "DataTable")
		{
			return $datatable
		}
		else
		{
			$datatable.Tables.Rows | Out-GridView
		}
	}
}