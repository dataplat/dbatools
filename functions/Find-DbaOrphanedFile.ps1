Function Find-DbaOrphanedFile
{
<#
.SYNOPSIS 
Find-DbaOrphanedFile finds orphaned database files; database files not associated with any attached database.

.DESCRIPTION
This command searches all directories associated with SQL database files for database files that are not currently in use by the SQL Server instance.
Get all the database files for all the database for the instance
Get the various directories of the instance and get all the present database files.
Compare which the two lists to see if there are any orphaned files and return the list

.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Path
Used to specify extra directories to search in addition to the default data and log directories

.PARAMETER Simple
Shows only the filenames
	
.PARAMETER FileType
Used to specify other filetypes in addition to ".mdf", ".ldf", ".ndf"
	
.NOTES 
Author: Sander Stad (@sqlstad), sqlstad.nl
Requires: sysadmin access on SQL Servers
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Find-DbaOrphanedFile

.EXAMPLE
Find-DbaOrphanedFile -SqlServer sqlserver2014a
Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE   
Find-DbaOrphanedFile -SqlServer sqlserver2014a -SqlCredential $cred
Does this, using SQL credentials for sqlserver2014a and Windows credentials for sql instance.

.EXAMPLE   
Find-DbaOrphanedFile -SqlServer sqlserver2014 -Path 'C:\Dir1', 'C:\Dir2'
Finds the orphaned files in the default directories but also the extra ones
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[parameter(Mandatory = $false)]
		[object]$SqlCredential,
		[parameter(Mandatory = $false)]
		[string[]]$Path,
		[string[]]$FileeTypes,
		[switch]$Simple
	)
	BEGIN
	{
		function Get-SqlFileStructure
		{
			param
			(
				[Parameter(Mandatory = $true, Position = 1)]
				[Microsoft.SqlServer.Management.Smo.SqlSmoObject]$smoserver
			)
			
			if ($smoserver.versionMajor -eq 8)
			{
				$sql = "select filename from sysaltfiles"
			}
			else
			{
				$sql = "SELECT Physical_Name AS filename FROM sys.master_files mf INNER JOIN  sys.databases db ON db.database_id = mf.database_id"
			}
			
			$dbfiletable = $smoserver.ConnectionContext.ExecuteWithResults($sql)
			$ftfiletable = $dbfiletable.Tables[0].Clone()
			$dbfiletable.Tables[0].TableName = "data"
			
			foreach ($db in $databaselist)
			{
				# Add support for Full Text Catalogs in Sql Server 2005 and below
				if ($server.VersionMajor -lt 10)
				{
					#$dbname = $db.name
					$fttable = $null = $smoserver.Databases[$database].ExecuteWithResults('sp_help_fulltext_catalogs')
					
					foreach ($ftc in $fttable.Tables[0].rows)
					{
						$name = $ftc.name
						$physical = $ftc.Path
						$logical = "sysft_$name"
						$null = $ftfiletable.Rows.add($database, "FULLTEXT", $logical, $physical)
					}
				}
			}
			
			$null = $dbfiletable.Tables.Add($ftfiletable)
			return $dbfiletable.Tables.Filename
		}
		
		$allfiles = @()
		$filetypes += ".mdf", ".ldf", ".ndf"
	}
	
	PROCESS
	{
		foreach ($servername in $sqlserver)
		{
			$server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential
			
			# Get all the database files
			$databasefiles = Get-SqlFileStructure -smoserver $server
			foreach ($file in $databasefiles)
			{
				$Path += Split-Path $file
			}
			
			# Get the default data and log directories from the instance
			$Path += $server.RootDirectory + "\DATA"
			$Path += Get-SqlDefaultPaths $server data
			$Path += Get-SqlDefaultPaths $server log
			$Path += $server.MasterDBPath
			$Path += $server.MasterDBLogPath
			
			# Clean it up
			$Path = $Path | ForEach-Object { $_.TrimEnd("\") } | Sort-Object -Unique
			
			# Create the file variable
			$orphanedfiles = @()
			$filesondisk = @()
			
			# Loop through each of the directories and get all the data and log file related files
			foreach ($directory in $Path)
			{
				$sql = "EXEC master.sys.xp_dirtree '$directory', 1, 1"
				Write-Debug $sql
				$server.ConnectionContext.ExecuteWithResults($sql).Tables.Subdirectory | ForEach-Object {
					if ($_ -ne $null)
					{
						if ($_.EndsWith($type)) # can prolly do in regex but unsure how
						{
							$filesondisk += "$directory\$_"
						}
					}
				}
			}
			
			# Compare the two lists and save the items that are not in the database file list 
			$orphanedfiles = (Compare-Object -ReferenceObject ($databasefiles) -DifferenceObject $filesondisk).InputObject
			
			foreach ($file in $orphanedfiles)
			{
				$allfiles += [pscustomobject]@{
					Server = $server.name
					Filename = $file
					RemoteFilename = Join-AdminUnc -Servername $servername -Filepath $file
				}
			}
		}
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
		
		if ($Simple -eq $true)
		{
			return ($allfiles | Select-Object filename).filename
		}
		
		return $allfiles
	}
}