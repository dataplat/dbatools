Function Install-SqlMaintenanceSolution
{
<#
.SYNOPSIS
Automatically installs or updates Ola Hallengren's Maintenance Solution. Wrapper for Install-SqlDatabaseBackup, Install-SqlDatabaseIntegrityCheck and Install-SqlMaintenanceSolution.

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
	
#>
	
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[string]$Path,
		[switch]$CreateJobs,
		[string]$JobNameSystemFull = 'DatabaseBackup - SYSTEM_DATABASES - FULL',
		[string]$JobNameUserDiff = 'DatabaseBackup - USER_DATABASES - DIFF',
		[string]$JobNameUserFull = 'DatabaseBackup - USER_DATABASES - FULL',
		[string]$JobNameUserLog = 'DatabaseBackup - USER_DATABASES - LOG',
		[string]$JobNameSystemIntegrityCheck = 'DatabaseIntegrityCheck - SYSTEM_DATABASES',
		[string]$JobNameUserIntegrityCheck = 'DatabaseIntegrityCheck - USER_DATABASES',
		[string]$JobNameUserMaintenanceSolution = 'MaintenanceSolution - USER_DATABASES',
		[string]$JobNameDeleteBackupHistory = 'sp_delete_backuphistory',
		[string]$JobNamePurgeBackupHistory = 'sp_purge_jobhistory',
		[string]$JobNameOutputFileCleanup = 'Output File Cleanup',
		[string]$JobNameComandLogCleanup = 'CommandLog Cleanup'
		)
	
	DynamicParam { if ($sqlserver) { return Get-ParamInstallDatabase -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		. "$PSScriptRoot\Install-OlaIntegrityCheck.ps1"
		. "$PSScriptRoot\Install-OlaMaintenanceSolution.ps1"
		. "$PSScriptRoot\Install-OlaDatabaseBackup.ps1"
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential -RegularUser
		$source = $sourceserver.DomainInstanceName
		
		Function Get-MaintenanceSolution
		{
			
			$url = 'https://ola.hallengren.com/scripts/MaintenanceSolution.sql'
			$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
			$sqlfile = "$temp\MaintenanceSolution.sql"
			
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
				
		# Used a dynamic parameter? Convert from RuntimeDefinedParameter object to regular array
		$InstallDatabase = $psboundparameters.InstallDatabase
		
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
		if ($InstallDatabase.length -eq 0)
		{
			$InstallDatabase = Show-SqlDatabaseList -SqlServer $sourceserver -Title "$actiontitle sp_WhoisActive" -Header $header -DefaultDb "master"
			
			if ($InstallDatabase.length -eq 0)
			{
				throw "You must select a database to $action the procedure"
			}
			
			if ($InstallDatabase -ne 'master')
			{
				Write-Warning "You have selected a database other than master. When you run Show-SqlWhoIsActive in the future, you must specify -Database $InstallDatabase"
			}
		}
		
		if ($Path.Length -eq 0)
		{
			$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
			$file = Get-ChildItem "$temp\MaintenanceSolution.sql" | Select -First 1
			$path = $file.FullName
			
			if ($path.Length -eq 0 -or $force -eq $true)
			{
				try
				{
					Write-Output "Downloading MaintenanceSolution.sql and $actioning."
					Get-MaintenanceSolution
				}
				catch
				{
					throw "Couldn't download MaintenanceSolution.sql. Please download and $action manually from https://ola.hallengren.com/scripts/MaintenanceSolution.sql."
				}
			}
			
			$path = (Get-ChildItem "$temp\MaintenanceSolution.sql" | Select -First 1).Name
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
			Write-Output "Finished $actioning MaintenanceSolution in $InstallDatabase on $SqlServer "
		}
	}
}