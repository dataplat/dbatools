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
		Write-Verbose "Connecting to $SqlServer"
		try
		{
			$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $Credential -ErrorVariable ConnectError
			
		}
		catch
		{
			Write-Warning $_
			continue
		}
		
		# STEP 1: Create and open runspace pool, setup runspaces array
		$pool = [RunspaceFactory]::CreateRunspacePool(1, [int]$env:NUMBER_OF_PROCESSORS+1)
		$pool.ApartmentState = "MTA"
		$pool.Open()
		$runspaces = @()
		
		# STEP 2: Create reusable scriptblock. This is the workhorse of the runspace. Think of it as a function.
		$scriptblock = {
			Param (
				[object]$server,
				[object]$file,
				[switch]$filelist
			)
			
			if ($file.FullName -ne $null) { $file = $file.FullName }
			
			$restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
			$device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem $file, FILE
			$restore.Devices.Add($device)
			
			# Sometimes ReadBackupHeader returns nothing because we're overwhelming it with runspaces :|
			# This seems like an issue with SqlConnection.
			
			while ($datatable -eq $null -and $attempts++ -lt 10)
			{
				try
				{
					$datatable = $restore.ReadBackupHeader($server)
				}
				catch
				{
					# Wait a lil bit then try again
					Start-Sleep -Milliseconds 200
				}
			}
			
			# Ensure that the file has been read, if not, let user know why
			
			try
			{
				if ($datatable -eq $null)
				{
					$datatable = $restore.ReadBackupHeader($server)
				}
			}
			catch
			{
				$shortname = Split-Path $file -Leaf
				if ($_.Exception -match "Cannot find server certificate with thumbprint")
				{
					return "The backup $shortname is encrypted and the server cannot find a matching certificate."
				}
				
				if (!(Test-SqlPath -SqlServer $server -Path $file))
				{
					return "File does $shortname not exist or access denied. The SQL Server service account may not have access to the source directory or the backup may be encrypted."
				}
				else
				{
					return "File list for $shortname could not be determined. This is likely due to the file not existing, the backup version being incompatible or unsupported, connectivity issues or tiemouts with the SQL Server, or the SQL Server service account does not have access to the source directory."
				}
			}
			
			$allfiles = $restore.ReadFileList($server)
			
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
			
			# Couldn't get the Convert-DbVersionToSqlVersion.ps1 to import in the runspace
			$datatable.rows[0].SQLVersion = switch ($dbversion)
			{
				856 { "SQL Server vNext CTP1" }
				852 { "SQL Server 2016" }
				829 { "SQL Server 2016 Prerelease" }
				782 { "SQL Server 2014" }
				706 { "SQL Server 2012" }
				684 { "SQL Server 2012 CTP1" }
				661 { "SQL Server 2008 R2" }
				660 { "SQL Server 2008 R2" }
				655 { "SQL Server 2008 SP2+" }
				612 { "SQL Server 2005" }
				611 { "SQL Server 2005" }
				539 { "SQL Server 2000" }
				515 { "SQL Server 7.0" }
				408 { "SQL Server 6.5" }
				default { $dbversion }
			}
			
			if ($Simple)
			{
				$datatable | Select-Object DatabaseName, BackupFinishDate, RecoveryModel, BackupSizeMB, CompressedBackupSizeMB, UserName, ServerName, SQLVersion, DatabaseCreationDate
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
	
	PROCESS
	{
		foreach ($file in $path)
		{
			$runspace = [PowerShell]::Create()
			$null = $runspace.AddScript($scriptblock)
			$null = $runspace.AddArgument($server)
			$null = $runspace.AddArgument($file)
			$null = $runspace.AddArgument($filelist)
			$runspace.RunspacePool = $pool
			$runspaces += [PSCustomObject]@{ Pipe = $runspace; Status = $runspace.BeginInvoke() }
		}
	}
	
	END
	{
		while ($runspaces.Status -ne $null)
		{
			$completed = $runspaces | Where-Object { $_.Status.IsCompleted -eq $true }
			
			foreach ($runspace in $completed)
			{
				$result = $runspace.Pipe.EndInvoke($runspace.Status)
				
				if ($result -ne $null)
				{
					if ($result.DatabaseName -eq $null)
					{
						Write-Warning ($result | Out-String)
					}
					else
					{
						$result
					}
					
					$runspace.Pipe.Dispose()
					$runspace.Status = $null
				}
				else
				{
					$runspace.Status = $runspace.Pipe.BeginInvoke()
				}
			}
		}
		
		$pool.Close()
		$pool.Dispose()
		$server.ConnectionContext.Disconnect()
	}
}