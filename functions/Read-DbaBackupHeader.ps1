Function Read-DbaBackupHeader
{
<#
.SYNOPSIS 
Reads and displays detailed information about a SQL Server backup

.DESCRIPTION
Reads full, differential and transaction log backups. An online SQL Server is required to parse the backup files and the path specified must be relative to that SQL Server.
	
.PARAMETER SqlServer
The SQL Server instance. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Path
Path to SQL Server backup file. This can be a full, differential or log backup file.
	
.PARAMETER Simple
Returns fewer columns for an easy overview
	
.PARAMETER FileList
Returns detailed information about the files within the backup	

.NOTES
Tags: DisasterRecovery, Backup, Restore
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Read-DbaBackupHeader

.EXAMPLE
Read-DbaBackupHeader -SqlServer sql2016 -Path S:\backups\mydb\mydb.bak

Logs into sql2016 using Windows authentication and reads the local file on sql2016, S:\backups\mydb\mydb.bak.
	
If you are running this command on a workstation and connecting remotely, remember that sql2016 cannot access files on your own workstation.

.EXAMPLE
Read-DbaBackupHeader -SqlServer sql2016 -Path \\nas\sql\backups\mydb\mydb.bak, \\nas\sql\backups\otherdb\otherdb.bak

Logs into sql2016 and reads two backup files - mydb.bak and otherdb.bak. The SQL Server service account must have rights to read this file.
	
.EXAMPLE
Read-DbaBackupHeader -SqlServer . -Path C:\temp\myfile.bak -Simple
	
Logs into the local workstation (or computer) and shows simplified output about C:\temp\myfile.bak. The SQL Server service account must have rights to read this file.

.EXAMPLE
$backupinfo = Read-DbaBackupHeader -SqlServer . -Path C:\temp\myfile.bak
$backupinfo.FileList
	
Displays detailed information about each of the datafiles contained in the backupset.

.EXAMPLE
Read-DbaBackupHeader -SqlServer . -Path C:\temp\myfile.bak -FileList
	
Also returns detailed information about each of the datafiles contained in the backupset.

.EXAMPLE
"C:\temp\myfile.bak", "\backupserver\backups\myotherfile.bak" | Read-DbaBackupHeader -SqlServer sql2016

Similar to running Read-DbaBackupHeader -SqlServer sql2016 -Path "C:\temp\myfile.bak", "\backupserver\backups\myotherfile.bak"
	
.EXAMPLE
Get-ChildItem \\nas\sql\*.bak | Read-DbaBackupHeader -SqlServer sql2016

Gets a list of all .bak files on the \\nas\sql share and reads the headers using the server named "sql2016". This means that the server, sql2016, must have read access to the \\nas\sql share.
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$Path,
		[switch]$Simple,
		[switch]$FileList
	)
	
	BEGIN
	{
		$LoopCnt = 1
		$FunctionName = $FunctionName = (Get-PSCallstack)[0].Command

		try
		{
			if ($sqlServer -isnot [Microsoft.SqlServer.Management.Smo.SqlSmoObject])
			{
					Write-Verbose "$FunctionName - Connecting to $SqlServer"
					$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ErrorVariable ConnectError
			}
			else
			{
				Write-Verbose "$FunctionName - Reusing connection to $SqlServer"
				$server = $sqlServer
			}
		}
		catch
		{
			Write-Warning $_
			continue
		}
	}
	
	PROCESS
	{
		
		$PathCount = $path.length
		Write-verbose "$FunctionName - $pathcount files to scan"
		foreach ($file in $path)
		{
			if ($file.FullName -ne $null) { $file = $file.FullName }
			Write-Progress -Id 1 -Activity Updating -Status 'Progress' -CurrentOperation "Scanning Restore headers on File $LoopCnt - $file"
			
			Write-Verbose "$FunctionName - Scanning file $file"
			$restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
			$device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem $file, FILE
			$restore.Devices.Add($device)
			if (Test-SqlPath -SqlServer $server -Path $file)
			{
				<#	try
					{
						$allfiles = $restore.ReadFileList($server)
					}
					catch
					{
						$shortname = Split-Path $file -Leaf
						if (!(Test-SqlPath -SqlServer $server -Path $file))
						{
							Write-Warning "File $shortname does not exist or access denied. The SQL Server service account may not have access to the source directory."
						}
						else
						{
							Write-Warning "File list for $shortname could not be determined. This is likely due to the file not existing, the backup version being incompatible or unsupported, connectivity issues or tiemouts with the SQL Server, or the SQL Server service account does not have access to the source directory."
						}
					}
					

				}#>
				try
				{
					$datatable = $restore.ReadBackupHeader($server)
				}
				catch
				{
					Write-Warning "$FunctionName - Problem with $file"
					Return
				}
				$fl = $datatable.Columns.Add("FileList", [object])
				#$datatable.rows[0].FileList = $allfiles.rows
				
				$mb = $datatable.Columns.Add("BackupSizeMB", [int])
				$mb.Expression = "BackupSize / 1024 / 1024"
				$gb = $datatable.Columns.Add("BackupSizeGB")
				$gb.Expression = "BackupSizeMB / 1024"
				
				if ($null -eq $datatable.Columns['CompressedBackupSize'])
				{
					$formula = "0"
				}
				else
				{
					$formula = "CompressedBackupSize / 1024 / 1024"
				}
				
				$cmb = $datatable.Columns.Add("CompressedBackupSizeMB", [int])
				$cmb.Expression = $formula
				$cgb = $datatable.Columns.Add("CompressedBackupSizeGB")
				$cgb.Expression = "CompressedBackupSizeMB / 1024"
				
				$null = $datatable.Columns.Add("SqlVersion")


				$null = $datatable.Columns.Add("BackupPath")
			#	$datatable.Columns["BackupPath"].DefaultValue = $Path
				$dbversion = $datatable.Rows[0].DatabaseVersion
				
			#	$datatable.Rows[0].SqlVersion = (Convert-DbVersionToSqlVersion $dbversion)
				$BackupSlot = 1
				ForEach ($row in $DataTable)
				{
					$row.SqlVersion = (Convert-DbVersionToSqlVersion $dbversion)
					$row.BackupPath = $file
					try
					{
						$restore.FileNumber = $BackupSlot
						$allfiles = $restore.ReadFileList($server)
					}
					catch
					{
						$shortname = Split-Path $file -Leaf
						if (!(Test-SqlPath -SqlServer $server -Path $file))
						{
							Write-Warning "File $shortname does not exist or access denied. The SQL Server service account may not have access to the source directory."
						}
						else
						{
							Write-Warning "File list for $shortname could not be determined. This is likely due to the file not existing, the backup version being incompatible or unsupported, connectivity issues or tiemouts with the SQL Server, or the SQL Server service account does not have access to the source directory."
						}
						
						#Write-Exception $_
						#return
					}
					$row.FileList = $allfiles
					$BackupSlot++

				}
			}
			else
			{
				Write-Warning "File $shortname does not exist or access denied. The SQL Server service account may not have access to the source directory."
				return
			}
			if ($Simple)
			{
				$datatable | Select-Object DatabaseName, BackupFinishDate, RecoveryModel, BackupSizeMB, CompressedBackupSizeMB, DatabaseCreationDate, UserName, ServerName, SqlVersion, BackupPath
			}
			elseif ($filelist)
			{
				$datatable.filelist
			}
			else
			{
				$datatable
			}
			
			Remove-Variable DataTable -ErrorAction SilentlyContinue
		}
	$LoopCnt++
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}
