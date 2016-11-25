Function Read-DbaBackupHeader
{
<#
.SYNOPSIS 
Simple template

.DESCRIPTION

.PARAMETER SqlServer
The SQL Server instance. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Read-DbaFileHeader

.EXAMPLE
Read-DbaFileHeader -SqlServer sqlserver2014a -Path S:\backups

Does this 
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[string[]]$Path,
		[switch]$Simple
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
				$filelist = $restore.ReadFileList($server)
			}
			catch
			{
				Write-Exception $_
				throw "File list could not be determined. This is likely due to connectivity issues or tiemouts with the SQL Server, the database version is incorrect, or the SQL Server service account does not have access to the file share. Script terminating."
			}
			
			$datatable = $restore.ReadBackupHeader($server)
			$fl = $datatable.Columns.Add("FileList",[object])
			$datatable.rows[0].FileList = $filelist.rows
			
			$mb = $datatable.Columns.Add("BackupSizeMB",[int])
			$mb.Expression = "BackupSize / 1024 / 1024"
			$gb = $datatable.Columns.Add("BackupSizeGB")
			$gb.Expression = "BackupSizeMB / 1024"
			
			
			$cmb = $datatable.Columns.Add("CompressedBackupSizeMB", [int])
			$cmb.Expression = "CompressedBackupSize / 1024 / 1024"
			$cgb = $datatable.Columns.Add("CompressedBackupSizeGB")
			$cgb.Expression = "CompressedBackupSizeMB / 1024"
			
		
			if ($Simple)
			{
				$datatable | Select-Object DatabaseName, BackupStartDate, RecoveryModel, BackupSizeMB, CompressedBackupSizeMB, UserName, ServerName, DatabaseVersion, DatabaseCreationDate
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