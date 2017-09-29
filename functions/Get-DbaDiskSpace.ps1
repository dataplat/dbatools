function Get-DbaDiskSpace {
	<#
		.SYNOPSIS
			Displays disk information for all local drives on a server.

		.DESCRIPTION
			Returns a custom object with server name, name of disk, label of disk, total size, free size, percent free, block size and filesystem.

			By default, this function only shows drives of types 2 and 3 (removable disk and local disk).

			Requires Windows administrator access on SQL Servers

		.PARAMETER ComputerName
			The server that you're connecting to.

		.PARAMETER Unit
			Specifies the units to use in displaying the disk space information. Valid options for this parameter are 'Bytes', 'KB', 'MB', 'GB', 'TB', and 'PB'. Default is GB.

		.PARAMETER CheckForSql
			If this switch is enabled, disks will be checked for SQL Server data and log files. Windows Authentication is always used for this.

		.PARAMETER SqlCredential
 			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$cred = Get-Credential, then pass $cred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER CheckFragmentation
			If this switch is enabled, fragmentation of all filesystems will be checked.

			This will increase the runtime of the function by seconds or even minutes per volume.

		.PARAMETER AllDrives
			If this switch is enabled, all drives visible on the server will be checked. By default, only drives of type 2 (removable) and 3 (local) are checked.

			For a list of all drive types, see https://msdn.microsoft.com/en-us/library/aa394515.aspx

		.PARAMETER Detailed
			If this switch is enabled, additional information about each drive is returned. This includes the filesystem (FAT32, NTFS, etc.) and the information provided by -CheckForSql and -AllDrives and volumes that would otherwise be excluded such as \\?\Volume* volumes.

		.PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

		.PARAMETER Confirm
			If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

		.NOTES
			Tags: Storage
			Author: Chrissy LeMaire (clemaire@gmail.com) & Jakob Bindslet (jakob@bindslet.dk)

			dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
			Copyright (C) 2016 Chrissy LeMaire
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaDiskSpace

		.EXAMPLE
			Get-DbaDiskSpace -ComputerName srv0042 | Format-Table -AutoSize

			Get disk space for the server srv0042.

			Server  Name Label  SizeInGB FreeInGB PercentFree BlockSize
			------  ---- -----  -------- -------- ----------- ---------
			srv0042 C:\  System   126,45   114,12       90,25      4096
			srv0042 E:\  Data1     97,62    96,33       98,67      4096
			srv0042 F:\  DATA2      29,2     29,2         100     16384

		.EXAMPLE
			Get-DbaDiskSpace -ComputerName srv0042 -Unit MB | Format-Table -AutoSize

			Get disk space for the server srv0042 and displays in megabytes (MB).

			Server  Name Label  SizeInMB  FreeInMB PercentFree BlockSize
			------  ---- -----  --------  -------- ----------- ---------
			srv0042 C:\  System   129481 116856,11       90,25      4096
			srv0042 E:\  Data1     99968  98637,56       98,67      4096
			srv0042 F:\  DATA2     29901  29900,92         100     16384

		.EXAMPLE
			Get-DbaDiskSpace -ComputerName srv0042, srv0007 -Unit TB | Format-Table -AutoSize

			Get disk space from two servers and displays in terabytes (TB).

			Server  Name Label  SizeInTB FreeInTB PercentFree BlockSize
			------  ---- -----  -------- -------- ----------- ---------
			srv0042 C:\  System     0,12     0,11       90,25      4096
			srv0042 E:\  Data1       0,1     0,09       98,67      4096
			srv0042 F:\  DATA2      0,03     0,03         100     16384
			srv0007 C:\  System     0,07     0,01       11,92      4096

		.EXAMPLE
			Get-DbaDiskSpace -ComputerName srv0042 -Detailed | Format-Table -AutoSize

			Get detailed disk space information.

			Server  Name                                              Label    SizeInGB FreeInGB PercentFree BlockSize IsSqlDisk FileSystem DriveType
			------  ----                                              -----    -------- -------- ----------- --------- --------- ---------- ---------
			srv0042 C:\                                               System     126,45   114,12       90,25      4096     False NTFS       Local Disk
			srv0042 E:\                                               Data1       97,62    96,33       98,67      4096     False ReFS       Local Disk
			srv0042 F:\                                               DATA2        29,2     29,2         100     16384     False FAT32      Local Disk
			srv0042 \\?\Volume{7a31be94-b842-42f5-af71-e0464a1a9803}\ Recovery     0,44     0,13       30,01      4096     False NTFS       Local Disk
			srv0042 D:\                                                               0        0           0               False            Compact Disk

	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias('ServerInstance', 'SqlInstance', 'SqlServer')]
		[String[]]$ComputerName,
		[ValidateSet('Bytes', 'KB', 'MB', 'GB', 'TB', 'PB')]
		[String]$Unit = 'GB',
		[Switch]$CheckForSql,
		[PSCredential]$SqlCredential,
		[Switch]$Detailed,
		[Switch]$CheckFragmentation,
		[Switch]$AllDrives
	)
	
	begin {
		$FunctionName = (Get-PSCallstack)[0].Command
		function Get-AllDiskSpace {
			$alldisks = @()
			$driveTypeName = @{
				'0' = 'Unknown';
				'1' = 'No Root Directory';
				'2' = 'Removable Disk';
				'3' = 'Local Disk';
				'4' = 'Network Drive';
				'5' = 'Compact Disk';
				'6' = 'RAM Disk'
			}
			
			if ($Detailed -or $AllDrives) {
				$driveTypes = 0 .. 6
			}
			else {
				$driveTypes = 2, 3
			}
			
			if ($Unit -eq 'Bytes') {
				$measure = '1'
			}
			else {
				$measure = "1$unit"
			}
			
			try {
				$disks = Get-WmiObject -Class Win32_Volume -Namespace 'root\CIMV2' -ComputerName $ipaddr | Where-Object DriveType -in ($driveTypes)
					if ($CheckFragmentation) {
						$disks = $disks | Select-Object SystemName, Name, DriveType, FileSystem, FreeSpace, Capacity, Label, BlockSize, @{ Name = 'FilePercentFragmentation'; Expression = { "$($_.defraganalysis().defraganalysis.FilePercentFragmentation)" }
					}
				}
				else {
					$disks = $disks | Select-Object SystemName, Name, DriveType, FileSystem, FreeSpace, Capacity, Label, BlockSize
				}
			}
			catch {
				Write-Warning "$FunctionName - Cannot connect to WMI on $server."
				return
			}
			
			if ($CheckForSql -or $Detailed) {
				$SqlInstances = @()
				$FailedToGetServiceInformation = $false
				$IsSqlEngineService = {
					$_.DisplayName -like 'SQL Server (*' -or $_.Name -eq 'MSSQLSERVER' -or $_.DisplayName -like 'MSSQL$*'
				}
				try {
					$sqlservices = Get-Service -ComputerName $ipaddr | Where-Object $IsSqlEngineService
				}
				catch {
					Write-Verbose "$FunctionName - Cannot retrieve service information from $server using Get-Service. Trying WMI."
					try {
						$sqlservices = Get-WmiObject Win32_Service -ComputerName $ipaddr | Where-Object $IsSqlEngineService
					}
					catch {
						Write-Warning "$FunctionName - Cannot retrieve service information from $server using Get-Service or WMI."
						$FailedToGetServiceInformation = $true
					}
				}
				
				foreach ($service in $sqlservices) {
					$instance = $service.DisplayName.Replace('SQL Server (', '')
					$instance = $instance.TrimEnd(')')
					$instance = $instance.Replace('MSSQL$', '')
					
					if ($instance -eq 'MSSQLSERVER') {
						$SqlInstances += $server
						Write-Verbose "$FunctionName - Instance resolved as $server."
					}
					else {
						$SqlInstances += "$server\$instance"
						Write-Verbose "$FunctionName - Instance resolved as $server\$instance."
					}
				}
			}
			
			foreach ($disk in $disks) {
				$diskname = $disk.Name
				if ($CheckForSql -or $Detailed) {
					$sqldisk = $false
					if ($FailedToGetServiceInformation) {
						$sqldisk = 'unknown'
					}
					else {
						foreach ($SqlInstance in $SqlInstances) {
							try {
								Write-Verbose "$FunctionName - Checking disk $diskname on $SqlInstance."
								$smoserver = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
								$sql = "Select count(*) as Count from sys.master_files where physical_name like '$diskname%'"
								$sqlcount = $smoserver.Databases['master'].ExecuteWithResults($sql).Tables[0].Count
								if ($sqlcount -gt 0) {
									$sqldisk = $true
									break
								}
							}
							catch {
								Write-Warning "$FunctionName - Can't connect to $server ($SqlInstance)."
								continue
							}
						}
					}
				}
				
				if (!$diskname.StartsWith('\\') -or $Detailed) {
					if ($disk.capacity -eq 0 -or [string]::IsNullOrEmpty($disk.capacity)) {
						$total = 0
						$free = 0
						$percentfree = 0
					}
					else {
						$total = [math]::round($disk.Capacity / $measure, 2)
						$free = [math]::round($disk.Freespace / $measure, 2)
						$percentfree = [math]::round(($disk.Freespace / $disk.Capacity) * 100, 2)
					}
					
					$diskinfo = [PSCustomObject]@{
						Server        = $server
						Name          = $diskname
						Label         = $disk.Label
						"SizeIn$unit" = $total
						"FreeIn$unit" = $free
						PercentFree   = $percentfree
						BlockSize     = $disk.BlockSize
					}
					
					if ($CheckForSql -or $Detailed) {
						Add-Member -Force -InputObject $diskinfo -MemberType Noteproperty IsSqlDisk -value $sqldisk
					}
					
					if ($Detailed) {
						Add-Member -Force -InputObject $diskinfo -MemberType Noteproperty FileSystem -value $disk.FileSystem
						Add-Member -Force -InputObject $diskinfo -MemberType Noteproperty DriveType -value $driveTypeName["$($disk.DriveType)"]
					}
					
					if ($CheckFragmentation) {
						Add-Member -Force -InputObject $diskinfo -MemberType Noteproperty PercentFragmented -value $disk.FilePercentFragmentation
					}
					$alldisks += $diskinfo
				}
			}
			return $alldisks
		}
		
		
		$processed = New-Object System.Collections.ArrayList
	}
	
	process {
		foreach ($server in $ComputerName) {
			if ($server -match '\\') {
				$server = $server.Split('\')[0]
			}
			
			if ($server -notin $processed) {
				$null = $processed.Add($server)
				Write-Verbose "$FunctionName - Connecting to $server."
			}
			else {
				continue
			}
			
			Write-Verbose "$FunctionName - Resolving computername."
			try {
				$ipaddr = ((Test-Connection -ComputerName $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address).IPAddressToString
			}
			catch {
				Write-Warning "$FunctionName - Can't resolve $server address."
				return
			}
			
			$data = Get-AllDiskSpace $server
			
			if ($data.Count -gt 1) {
				$data.GetEnumerator() | ForEach-Object { $_ }
			}
			else {
				$data
			}
		}
	}
}