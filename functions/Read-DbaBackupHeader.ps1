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
Path to SQL Serer backup file. This can be a full, differential or log backup file.
	
.PARAMETER Simple
Returns fewer columns for an easy overview
	
.PARAMETER FileList
Returns detailed information about the files within the backup	

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Read-DbaFileHeader

.EXAMPLE
Read-DbaFileHeader -SqlServer sql2016 -Path S:\backups\mydb\mydb.bak

Logs into sql2016 using Windows authentication and reads the local file on sql2016, S:\backups\mydb\mydb.bak.
	
If you are running this command on a workstation and connecting remotely, remember that sql2016 cannot access files on your own workstation.

.EXAMPLE
Read-DbaFileHeader -SqlServer sql2016 -Path \\nas\sql\backups\mydb\mydb.bak, \\nas\sql\backups\otherdb\otherdb.bak

Logs into sql2016 and reads two backup files - mydb.bak and otherdb.bak. The SQL Server service account must have rights to read this file.
	
.EXAMPLE
Read-DbaFileHeader -SqlServer . -Path C:\temp\myfile.bak -Simple
	
Logs into the local worksation and shows simplified output about C:\temp\myfile.bak. The SQL Server service account must have rights to read this file.

.EXAMPLE
$backupinfo = Read-DbaFileHeader -SqlServer . -Path C:\temp\myfile.bak
$backupinfo.FileList
	
Displays detailed information about each of the datafiles contained in the backupset.

.EXAMPLE
Read-DbaFileHeader -SqlServer . -Path C:\temp\myfile.bak -FileList
	
Also returns detailed information about each of the datafiles contained in the backupset.
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[string[]]$Path,
		[switch]$Simple,
		[switch]$FileList
	)
	
	BEGIN
	{
		
		$server = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
	}
	
	PROCESS
	{
		foreach ($file in $path)
		{
			$restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
			$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem $file, "FILE"
			$restore.Devices.Add($device)
			
			try
			{
				$allfiles = $restore.ReadFileList($server)
			}
			catch
			{
				Write-Warning "File list could not be determined. This is likely due to connectivity issues or tiemouts with the SQL Server, the database version is incorrect, or the SQL Server service account does not have access to the file share."
				Write-Exception $_
				return
			}
			
			$datatable = $restore.ReadBackupHeader($server)
			$fl = $datatable.Columns.Add("FileList", [object])
			$datatable.rows[0].FileList = $allfiles.rows
			
			$mb = $datatable.Columns.Add("BackupSizeMB", [int])
			$mb.Expression = "BackupSize / 1024 / 1024"
			$gb = $datatable.Columns.Add("BackupSizeGB")
			$gb.Expression = "BackupSizeMB / 1024"
			
			
			$cmb = $datatable.Columns.Add("CompressedBackupSizeMB", [int])
			$cmb.Expression = "CompressedBackupSize / 1024 / 1024"
			$cgb = $datatable.Columns.Add("CompressedBackupSizeGB")
			$cgb.Expression = "CompressedBackupSizeMB / 1024"
			
			$version = $datatable.Columns.Add("SQLVersion")
			$dbversion = $datatable.rows[0].DatabaseVersion
			
			switch ($dbversion)
			{
				856 { $dbversion = "SQL Server vNext CTP1" }
				852 { $dbversion = "SQL Server 2016" }
				829 { $dbversion = "SQL Server 2016 Prerelease" }
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
			}
			
			$datatable.rows[0].SQLVersion = $dbversion
			
			if ($Simple)
			{
				$datatable | Select-Object DatabaseName, BackupStartDate, RecoveryModel, BackupSizeMB, CompressedBackupSizeMB, UserName, ServerName, SQLVersion, DatabaseCreationDate
			}
			elseif ($filelist)
			{
				$datatable.filelist
			}
			else
			{
				$datatable
			}
		}
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}