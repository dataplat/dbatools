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
		function Get-SqlFileStructure
		{
			param
			(
				[Parameter(Mandatory = $true, Position = 1)]
				[Microsoft.SqlServer.Management.Smo.SqlSmoObject]$smoserver
			)	
			# use sysaltfiles in lower versions
			# this will fail with filestream stuff, but as that is not possible on these versions, no problem.					
			

			$missingfiles = $smoserver.ConnectionContext.ExecuteWithResults($sql)			
			$ftfiletable = $dbfiletable.Tables[0].Clone()
			$dbfiletable.Tables[0].TableName = "data"				
			$null = $dbfiletable.Tables.Add($ftfiletable)
			return $dbfiletable.Tables
		}

		function Format-Comparison 
		{
			param
			(
				$PathList
			)	
			# use sysaltfiles in lower versions
			# this will fail with filestream stuff, but as that is not possible on these versions, no problem.
			$q1 = "create table #enum (id int identity, fs_filename nvarchar(512), depth int, is_file int)"
			$q2 = "insert #enum(fs_filename, depth, is_file) exec xp_dirtree 'dirname',1,1"
			if ($smoserver.versionMajor -le 8)
			{
				$query_files_sql = @"	

					select e.fs_filename as filename
					from #enum e 
					left join 
					( 
						select reverse(substring(reverse(filename), 0, CHARINDEX('\',reverse(filename)))) [current_database_files]
						from sys.sysaltfiles m
					) mf on mf.[current_database_files] = e.fs_filename
					where 
							fs_filename NOT IN ( 
							'xtp'
							, '5'
							, '`$FSLOG'
							, '`$HKv2' 
							, 'filestream.hdr' 
							) 
					and [current_database_files] is null
"@				
			}
			else
			{
				$query_files_sql = @"	

					select e.fs_filename as filename
					from #enum e 
					left join 
					( 
						select reverse(substring(reverse(physical_name), 0, CHARINDEX('\',reverse(physical_name)))) [current_database_files]
						from sys.master_files m
					) mf on mf.[current_database_files] = e.fs_filename
					where 
							fs_filename NOT IN ( 
							'xtp'
							, '5'
							, '`$FSLOG'
							, '`$HKv2' 
							, 'filestream.hdr' 
							) 
					and [current_database_files] is null
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
		TRY { 
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
				$Paths = $Paths | % { "$_".TrimEnd("\") } | Sort-Object -Unique								
				$Paths = $Paths | ? {$_}  # Remove blanks
				Write-Debug "Filtering paths"
								
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
				
				# Create the file variable
				$orphanedfiles = @()
				$filesondisk = @()
				write-debug "Query and paths:"			
				write-host $Paths
				$orphan_query = $( Format-Comparison $Paths )				 		
				$orphanedfiles += $server.Databases['master'].ExecuteWithResults($orphan_query).Tables[0].filename 				
			
			write-debug "Comparing files and database files"
			# Compare the two lists and save the items that are not in the database file list 		
			foreach ($file in $orphanedfiles)
			{
				$allfiles += [pscustomobject]@{
					Server = $server.name
					Filename = $file
					RemoteFilename = Join-AdminUnc -Servername $server.netname -Filepath $file
				}
			}
		}
		}
			catch {
				write-host "error" -foregroundcolor red
				write-host $_
				"$($_.InvocationInfo.ScriptName)($($_.InvocationInfo.ScriptLineNumber)): $($_.InvocationInfo.Line)"
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