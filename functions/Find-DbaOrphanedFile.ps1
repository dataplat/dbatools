Function Find-DbaOrphanedFile
{
<#
.SYNOPSIS 
Find-DbaOrphanedFile finds orphaned database files. Orphaned database files are files not associated with any attached database.

.DESCRIPTION
This command searches all directories associated with SQL database files for database files that are not currently in use by the SQL Server instance.

By default, it looks for orphaned .mdf, .ldf and .ndf files in the root\data directory, the default data path, the default log path, the system paths and any directory in use by any attached directory.
	
You can specify additional filetypes using the -FileType parameter, and additional paths to search using the -Path parameter.
	
.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Path
Used to specify extra directories to search in addition to the default data and log directories.

.PARAMETER FileType
Used to specify other filetypes in addition to mdf, ldf, ndf. No dot required, just pass the extension.
	
.PARAMETER LocalOnly
Shows only the local filenames
	
.PARAMETER RemoteOnly
Shows only the remote filenames
	
.NOTES 
Author: Sander Stad (@sqlstad), sqlstad.nl
Requires: sysadmin access on SQL Servers
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

Thanks to Paul Randal's notes on FILESTREAM which can be found at http://www.sqlskills.com/blogs/paul/filestream-directory-structure/

.LINK
https://dbatools.io/Find-DbaOrphanedFile

.EXAMPLE
Find-DbaOrphanedFile -SqlServer sqlserver2014a
Logs into the SQL Server "sqlserver2014a" using Windows credentials and searches for orphaned files. Returns server name, local filename, and unc path to file.

.EXAMPLE   
Find-DbaOrphanedFile -SqlServer sqlserver2014a -SqlCredential $cred
Logs into the SQL Server "sqlserver2014a" using alternative credentials and searches for orphaned files. Returns server name, local filename, and unc path to file.

.EXAMPLE   
Find-DbaOrphanedFile -SqlServer sql2014 -Path 'E:\Dir1', 'E:\Dir2'
Finds the orphaned files in "E:\Dir1" and "E:Dir2" in addition to the default directories.
	
.EXAMPLE   
Find-DbaOrphanedFile -SqlServer sql2014 -LocalOnly
Returns only the local filepath. Using LocalOnly with multiple servers is not recommended since it does not return the associated server name.

.EXAMPLE   
Find-DbaOrphanedFile -SqlServer sql2014 -RemoteOnly
Returns only the remote filepath. Using LocalOnly with multiple servers is not recommended since it does not return the associated server name.
	
.EXAMPLE   
Find-DbaOrphanedFile -SqlServer sql2014, sql2016 -FileType fsf, mld
Finds the orphaned ending with ".fsf" and ".mld" in addition to the default filetypes ".mdf", ".ldf", ".ndf" for both the servers sql2014 and sql2016.
	

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
		[string[]]$FileType,
		[switch]$LocalOnly,
		[switch]$RemoteOnly
	)
	BEGIN
	{		
		function Format-Comparison 
		{
			param
			(
				$PathList
			)	
			# use sysaltfiles in lower versions
			# this will fail with filestream stuff, but as that is not possible on these versions, no problem.
			$q1 = "CREATE TABLE #enum ( id int IDENTITY, fs_filename nvarchar(512), depth int, is_file int, parent nvarchar(512) ); DECLARE @dir nvarchar(512);"
			$q2 = @"
				SET @dir = 'dirname';

				INSERT INTO #enum( fs_filename, depth, is_file )
				EXEC xp_dirtree @dir, 1, 1;

				UPDATE #enum
				SET parent = @dir
				WHERE parent IS NULL;
"@
			if ($smoserver.versionMajor -le 8)
			{
				$query_files_sql = @"	
					SELECT e.fs_filename AS filename, parent
					FROM #enum AS e
						LEFT JOIN
					(
						SELECT REVERSE(SUBSTRING(REVERSE(filename), 0, CHARINDEX('\', REVERSE(filename)))) AS [current_database_files]
						FROM sys.sysaltfiles AS m
					) AS mf
						ON mf.[current_database_files] = e.fs_filename
					WHERE fs_filename NOT IN( 'xtp', '5', '`$FSLOG', '`$HKv2', 'filestream.hdr' ) AND 
						[current_database_files] IS NULL AND 
						is_file = 1;
"@				
			}
			else
			{
				$query_files_sql = @"	
					SELECT e.fs_filename AS filename, parent
					FROM #enum AS e
						LEFT JOIN
					(
						SELECT REVERSE(SUBSTRING(REVERSE(physical_name), 0, CHARINDEX('\', REVERSE(physical_name)))) AS [current_database_files]
						FROM sys.master_files AS m
					) AS mf
						ON mf.[current_database_files] = e.fs_filename
					WHERE fs_filename NOT IN( 'xtp', '5', '`$FSLOG', '`$HKv2', 'filestream.hdr' ) AND 
						[current_database_files] IS NULL AND 
						is_file = 1;
"@
			}
			$sql = $q1
			$sql += $( $PathList | % { "$([System.Environment]::Newline)$($q2 -Replace 'dirname',$_)" } ) 	
			$sql += $query_files_sql				
			write-debug $sql		
			return $sql
		}				
		$Paths = @()
		$allfiles = @()
		$FileType += "mdf", "ldf", "ndf"
		$systemfiles = "distmdl.ldf", "distmdl.mdf", "mssqlsystemresource.ldf", "mssqlsystemresource.mdf"
	}
	
	PROCESS
	{
		foreach ($servername in $sqlserver)
		{			
			$server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential									
				
			# Get the default data and log directories from the instance
			Write-Debug "Adding paths"
			$Paths += $server.RootDirectory + "\DATA"
			$Paths += Get-SqlDefaultPaths $server data
			$Paths += Get-SqlDefaultPaths $server log
			$Paths += $server.MasterDBPath
			$Paths += $server.MasterDBLogPath
			$Paths += $Path	
			if ($server.VersionMajor -lt 10)			
			{
				# Add support for Full Text Catalogs in Sql Server 2005 and below
				foreach ($db in $databaselist)
				{
					if ($smoserver.Databases[$database].ExecuteWithResults("SELECT FULLTEXTSERVICEPROPERTY('IsFullTextInstalled')").Tables[0][0] -eq 1)
					{
						Write-Debug "Gathering Full Text Information"
						$fttable = $smoserver.Databases[$database].ExecuteWithResults('sp_help_fulltext_catalogs')						
						foreach ($ftc in $fttable.Tables[0].rows)
						{
							$Paths += $ftc.Path
						}
					}
				}
			}
			$Paths = $Paths | % { "$_".TrimEnd("\") } | Sort-Object -Unique
			$orphanedfiles = @()									
			$orphan_query = $( Format-Comparison $Paths )				 		
			$orphanedfiles += $server.Databases['master'].ExecuteWithResults($orphan_query).Tables[0] | % { "$($_.parent)\$($_.filename)" }
			$orphanedfiles = $orphanedfiles | ? { $_ }   # Remove blanks
			$matching_orphans = @()				

			Write-Debug "Found $($orphanedfiles.count) loose files."
			Write-Debug "Comparing to $($FileType.count) file types."
			foreach ($file in  $orphanedfiles) 
			{ 
				foreach ($type in $FileType) 
				{
					write-debug "Comparing $file to *$type"
					if ($file -like "*$type")
					{								
						$matching_orphans += $file
					}
				} 
			}					 		
			foreach ($file in $matching_orphans)
			{
				$allfiles += [pscustomobject]@{
					Server = $server.name
					Filename = $file
					RemoteFilename = Join-AdminUnc -Servername $server.netname -Filepath $file
				}
			}
		}
	}					
	END
	{
		$server.ConnectionContext.Disconnect()
		
		if ($LocalOnly -eq $true)
		{
			return ($allfiles | Select-Object filename).filename
		}
		
		if ($RemoteOnly -eq $true)
		{
			return ($allfiles | Select-Object remotefilename).remotefilename
		}
		
		if ($allfiles.count -eq 0)
		{
			Write-Output "No orphaned files found"
		}
		return $allfiles
	}
}