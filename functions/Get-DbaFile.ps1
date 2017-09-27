Function Get-DbaFile {
<#
.SYNOPSIS 
Get-DbaFile finds files in any directory specified on a remote SQL Server

.DESCRIPTION
This command searches all specified directories, allowing a DBA to see file information on a server without direct access

You can filter by extension using the -FileType parameter. By default, the default data directory will be returned. You can provide and additional paths to search using the -Path parameter.
	
.PARAMETER SqlInstance
The SQL Server instance. 

.PARAMETER SqlCredential
Allows you to login to servers using alternative credentials

.PARAMETER Path
Used to specify extra directories to search in addition to the default data directory.

.PARAMETER FileType
Used to specify filter by filetype. No dot required, just pass the extension.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages
	
.NOTES
Tags: Discovery
Author: Brandon Abshire, netnerds.net

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaFile

.EXAMPLE
Get-DbaFile -SqlInstance sqlserver2014a -Path E:\Dir1
Logs into the SQL Server "sqlserver2014a" using Windows credentials and searches E:\Dir for all files

.EXAMPLE   
Get-DbaFile -SqlInstance sqlserver2014a -SqlCredential $cred -Path 'E:\sql files'
Logs into the SQL Server "sqlserver2014a" using alternative credentials and returns all files in 'E:\sql files'

.EXAMPLE
$all = Get-DbaDefaultPath -SqlInstance sql2014
Get-DbaFile -SqlInstance sql2014 -Path $all.Data, $all.Log, $all.Backup
Returns the files in the default data, log and backup directories on sql2014 
	
.EXAMPLE   
Get-DbaFile -SqlInstance sql2014 -Path 'E:\Dir1', 'E:\Dir2'
Returns the files in "E:\Dir1" and "E:Dir2" on sql2014
	
.EXAMPLE   
Get-DbaFile -SqlInstance -Path 'E:\Dir1' sql2014, sql2016 -FileType fsf, mld
Finds files in E:\Dir1 ending with ".fsf" and ".mld" for both the servers sql2014 and sql2016.
	
.EXAMPLE   
Get-DbaFile -SqlInstance -Path 'E:\Dir1' sql2014, sql2016 -FileType fsf, mld
Finds files in E:\Dir1 ending with ".fsf" and ".mld" for both the servers sql2014 and sql2016.  
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[string[]]$Path,
		[string[]]$FileType,
		[switch]$Silent
	)
	begin {
		
		function Get-SQLDirTreeQuery {
			param
			(
				$PathList
			)
			
			$q1 = "IF EXISTS(SELECT 1 FROM tempdb.dbo.sysobjects WHERE id = OBJECT_ID('tempdb..#enum'))
                    DROP TABLE #enum; 
                                       
                    CREATE TABLE #enum ( id int IDENTITY, fs_filename nvarchar(512), depth int, is_file int, parent nvarchar(512) ); DECLARE @dir nvarchar(512);"
			
			$q2 = "SET @dir = 'dirname';

				INSERT INTO #enum( fs_filename, depth, is_file )
				EXEC xp_dirtree @dir, 1, 1;

				UPDATE #enum
				SET parent = @dir,
				fs_filename = ltrim(rtrim(fs_filename))
				WHERE parent IS NULL;"
			
			$query_files_sql = "SELECT e.fs_filename AS filename, e.parent FROM #enum AS e WHERE is_file = 1;"
			
			# build the query string based on how many directories they want to enumerate
			$sql = $q1
			$sql += $($PathList | Where-Object { $_ -ne '' } | ForEach-Object { "$([System.Environment]::Newline)$($q2 -Replace 'dirname', $_)" })
			$sql += $query_files_sql
			Write-Message -Level Debug -Message $sql
			return $sql
		}
		
		function Format-Path {
			param ($path)
			$path = $path.Trim()
			#Thank you windows 2000
			$path = $path -replace '[^A-Za-z0-9 _\.\-\\:]', '__'
			return $path
		}
		
		if ($FileType) {
			$FileTypeComparison = $FileType | ForEach-Object { $_.ToLower() } | Where-Object { $_ } | Sort-Object | Get-Unique
		}
	}
	
	process {
		foreach ($instance in $SqlInstance) {

			$paths = @()
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			# Get the default data and log directories from the instance
			if (-not (Test-Bound -Parameter Path)) { $Path = (Get-DbaDefaultPath -SqlInstance $server).Data }
			
			Write-Message -Level Verbose -Message "Adding paths"
			$paths = $Path | ForEach-Object { "$_".TrimEnd("\") } | Sort-Object | Get-Unique
			$sql = Get-SQLDirTreeQuery $paths
			$datatable = $server.Query($sql)
			
			Write-Message -Level Verbose -Message "$($datatable.Rows.Count) files found."
			if ($FileTypeComparison) {
				foreach ($row in $datatable) {
					foreach ($type in $FileTypeComparison) {
						if ($row.filename.ToLower().EndsWith($type)) {
							$fullpath = [IO.Path]::combine($row.parent, $row.filename)
							[pscustomobject]@{
								ComputerName   = $server.NetName
								InstanceName   = $server.ServiceName
								SqlInstance    = $server.DomainInstanceName
								Filename  = $fullpath
								RemoteFilename = Join-AdminUnc -Servername $server.netname -Filepath $fullpath
							} | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, RemoteFilename
						}
					}
				}
			}
			else {
				foreach ($row in $datatable) {
					$fullpath = [IO.Path]::combine($row.parent, $row.filename)
					[pscustomobject]@{
						ComputerName   = $server.NetName
						InstanceName   = $server.ServiceName
						SqlInstance    = $server.DomainInstanceName
						Filename  = $fullpath
						RemoteFilename = Join-AdminUnc -Servername $server.netname -Filepath $fullpath
					} | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, RemoteFilename
				}
			}
		}
	}
}