Function Install-OlaDatabaseBackup
{
<#
.SYNOPSIS
Automatically installs or updates Ola Hallengren's Maintenance Solution. Wrapper for Install-SqlDatabaseBackup, Install-SqlDatabaseIntegrityCheck and Install-SqlIndexOptimize.

.DESCRIPTION
This command downloads and installs Maintenance Solution, with Ola's permission.
	
To read more about Maintenance Solution, please visit https://ola.hallengren.com
	
.PARAMETER SqlServer
The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER OutputDatabaseName
Outputs just the database name instead of the success message

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
https://dbatools.io/Install-OlaDatabaseBackup

.EXAMPLE
Install-OlaDatabaseBackup -SqlServer sqlserver2014a -Database master

Installs Maintenance Plans to sqlserver2014a's master database. Logs in using Windows Authentication.
	
.EXAMPLE   
Install-OlaDatabaseBackup -SqlServer sqlserver2014a -SqlCredential $cred

Pops up a dialog box asking which database on sqlserver2014a you want to install the proc to. Logs into SQL Server using SQL Authentication.
	
#>
	
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[string]$Databases,
		[string]$Directory,
		[ValidateSet('FULL', 'DIFF', 'LOG')]
		[string]$BackupType,
		[switch]$Verify,
		[Parameter(Mandatory = $true, HelpMessage = "Specify cleanup time in hours. Infinite = 0, 7d = 168, 30d = 720, 60d = 1440, 90d = 2160, 365d = 8760")]
		[int]$CleanupTime,
		[int]$CleanupTimeDays,
		[ValidateSet('AfterBackup', 'BeforeBackup')]
		[string]$CleanupMode = 'AfterBackup',
		[ValidateSet('Default', 'Yes', 'No')]
		[string]$Compress,
		[switch]$CopyOnly,
		[switch]$ChangeBackupType,
		[parameter(ParameterSetName = "OtherSoftware")]
		[ValidateSet('Native', 'Litespeed', 'SQLBackup', 'SQLSafe')]
		[string]$BackupSoftware = 'Native',
		[switch]$CheckSum,
		[int]$BlockSize,
		[int]$BufferCount,
		[int]$MaxTransferSize,
		[ValidateLength(0, 64)]
		[int]$NumberOfFiles,
		[parameter(ParameterSetName = "OtherSoftware")]
		[ValidateScript({
				switch ($BackupSoftware)
				{
					'Default' { return $false }
					'Litespeed' { $_ -in 0..8 }
					'SQLBackup' { $_ -in 0..4 }
					'SQLSafe' { $_ -in 1..4 }
				}
			})]
		[int]$CompressionLevel,
		[string]$Description,
		[parameter(ParameterSetName = "OtherSoftware")]
		[ValidateScript({
				switch ($BackupSoftware)
				{
					'Default' { return $false }
					{ 'Litespeed' -or 'SQLBackup' -or 'SQLSafe' } { $_ -in 1..32 }
				}
			})]
		[int]$Threads,
		[ValidateScript({
				switch ($BackupSoftware)
				{
					'Litespeed' { return $true }
					Default { return $false }
				}
			})]
		[Alias("ThrottlePercent")]
		[int]$Throttle,
		[switch]$Encrypt,
		[ValidateSet('RC2_40', 'RC2_56', 'RC2_112', 'RC2_128', 'TRIPLE_DES_3KEY', 'RC4_128', 'AES_128', 'AES_192', 'AES_256')]
		[string]$EncryptionAlgorithm,
		# Anyone know where I can find this?
		[string]$EncryptionKey,
		[switch]$ReadWriteFileGroups,
		[switch]$OverrideBackupPreference,
		[switch]$NoRecovery,
		[string]$URL,
		[string]$MirrorDirectory,
		[Parameter(Mandatory = $false, HelpMessage = "Specify cleanup time in hours. Infinite = 0, 7d = 168, 30d = 720, 60d = 1440, 90d = 2160, 365d = 8760")]
		[int]$MirrorCleanupTime,
		[ValidateSet('AfterBackup', 'BeforeBackup')]
		[string]$MirrorCleanupMode = 'AfterBackup',
		[switch]$LogToTable,
		[switch]$OutputOnly,
		[string]$Header = "Scripts not found. To deploy, select a database or hit cancel to quit."
	)
	
	DynamicParam
	{
		if ($sqlserver)
		{
			# Auto populates:
			#[string]$InstallDatabase,
			#[string]$Credential,
			#[string]$ServerCertificate,
			#[string]$ServerAsymmetricKey,
			return (Get-ParamMaintenanceSolution -SqlServer $sqlserver -SqlCredential $SqlCredential) } }
	
	
	BEGIN
	{
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential -RegularUser
		$source = $sourceserver.DomainInstanceName
		$InstallDatabase = $psboundparameters.InstallDatabase
		
		# Parameter switching and cleaning
		
		if ($CleanupTime -gt 0 -and $CleanupTimeDays -gt 0)
		{
			throw "You must pick either CleanupTime or CleanupTimeDays"	
		}
		
		switch ($CleanupMode)
		{
			'AfterBackup' { $CleanupMode = 'AFTER_BACKUP' }
			'BeforeBackup' { $CleanupMode = 'BEFORE_BACKUP' }
		}
		
		switch ($MirrorCleanupMode)
		{
			'AfterBackup' { $MirrorCleanupMode = 'AFTER_BACKUP' }
			'BeforeBackup' { $MirrorCleanupMode = 'BEFORE_BACKUP' }
		}
		
		switch ($BackupSoftware)
		{
			'Native' { $BackupSoftware = $null }
		}
		
		switch ($Compress)
		{
			'Default' { $Compress = $null }
		}
		
		switch ($OutputOnly)
		{
			$true { $Execute = $false }
			$false { $Execute = $true }
		}
		
		if ($Directory.Length -gt 0)
		{
			Test-SqlPath -SqlServer $sourceserver -Path $Directory
		}
	
		if ($MirrorDirectory.Length -gt 0)
		{
			Test-SqlPath -SqlServer $sourceserver -Path $MirrorDirectory
		}
		
		if ($CleanupTimeDays -gt 0)
		{
			$CleanupTime = $CleanupTimeDays*24
		}
		
		$switches = 'Verify', 'CopyOnly', 'ChangeBackupType', 'CheckSum', 'Encrypt', 'ReadWriteFileGroups', 'OverrideBackupPreference', 'NoRecovery', 'LogToTable', 'Execute'
		
		foreach ($switch in $switches)
		{
			$paramvalue = Get-Variable -Name $switch -ValueOnly
			
			if ($paramvalue -eq $true)
			{
				Set-Variable -Name $switch -Value 'Y'
			}
			else
			{
				Set-Variable -Name $switch -Value 'N'
			}
			
		}
		
		
		Function Get-DatabaseBackup
		{
			
			$url = 'https://ola.hallengren.com/scripts/DatabaseBackup.sql'
			$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
			$sqlfile = "$temp\DatabaseBackup.sql"
			
			try
			{
				Invoke-WebRequest $url -OutFile $sqlfile
			}
			catch
			{
				#try with default proxy and usersettings
				(New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
				Invoke-WebRequest $url -OutFile $sqlfile
			}
			
			# Unblock if there's a block
			Unblock-File $sqlfile -ErrorAction SilentlyContinue
		}
		
		if ($Header -like '*update*')
		{
			$action = "update"
		}
		else
		{
			$action = "install"
		}
		
		$textinfo = (Get-Culture).TextInfo
		$actiontitle = $textinfo.ToTitleCase($action)
		
		if ($action -eq "install")
		{
			$actioning = "installing"
		}
		else
		{
			$actioning = "updating"
		}
	}
	
	PROCESS
	{
		Write-Warning "hello"
		return
		if ($InstallDatabase.length -eq 0)
		{
			$InstallDatabase = Show-SqlDatabaseList -SqlServer $sourceserver -Title "$actiontitle Maintenance Plans" -Header $header -DefaultDb "master"
			
			if ($InstallDatabase.length -eq 0)
			{
				throw "You must select a database to $action the procedure"
			}
		}
		
		if ($Path.Length -eq 0)
		{
			$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
			$file = Get-ChildItem "$temp\DatabaseBackup.sql" | Select -First 1
			$path = $file.FullName
			
			if ($path.Length -eq 0 -or $force -eq $true)
			{
				try
				{
					Write-Output "Downloading Maintenance Plans zip file, unzipping and $actioning."
					Get-DatabaseBackup
				}
				catch
				{
					throw "Couldn't download Maintenance Plans. Please download and $action manually from http://sqlblog.com/files/folders/42453/download.aspx."
				}
			}
			
			$path = (Get-ChildItem "$temp\who*active*.sql" | Select -First 1).Name
			$path = "$temp\$path"
		}
		
		if ((Test-Path $Path) -eq $false)
		{
			throw "Invalid path at $path"
		}
		
		$sql = [IO.File]::ReadAllText($path)
		$sql = $sql -replace 'USE master', ''
		$batches = $sql -split "GO\r\n"
		
		foreach ($batch in $batches)
		{
			try
			{
				$null = $sourceserver.databases[$InstallDatabase].ExecuteNonQuery($batch)
				
			}
			catch
			{
				Write-Exception $_
				throw "Can't $action stored procedure. See exception text for details."
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		
		if ($OutputDatabaseName -eq $true)
		{
			return $InstallDatabase
		}
		else
		{
			Write-Output "Finished $actioning Maintenance Plans in $InstallDatabase on $SqlServer "
		}
	}
}