function Install-DbaMaintenanceSolution {
    <#
    .SYNOPSIS
        Download and Install SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com)
    .DESCRIPTION
        This script will download and install the latest version of SQL Server Maintenance Solution created by Ola Hallengren
    
	.PARAMETER SqlInstance
        The target SQL Server instance
	
	.PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
        To connect as a different Windows user, run PowerShell as that user.        
   
	.PARAMETER Database
        The database where Ola Hallengren's solution will be installed. Defaults to master
    
	.PARAMETER BackupLocation
        Location of the backup root directory. If this is not supplied, the default backup directory will be used.
    
	.PARAMETER CleanupTime
        Time in hours, after which backup files are deleted
    
	.PARAMETER OutputFileDirectory
        Specify the output file directory
    
	.PARAMETER ReplaceExisting
        If the objects are already present in the chosen database, we drop and recreate them
 
	.PARAMETER WhatIf
	Shows what would happen if the command were to run. No actions are actually performed.

	.PARAMETER Confirm
	Prompts you for confirmation before executing any changing operations within the command.

	.PARAMETER Silent
	Use this switch to disable any kind of verbose messages

	.NOTES
        Author: Viorel Ciucu, viorel.ciucu@gmail.com, cviorel.com

    .LINK
        http://dbatools.io/Install-DbaMaintenanceSolution
	
	.EXAMPLE
        This will create the Ola Hallengren's Solution objects. Existing objects are not affected in any way.
        Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -BackupLocation "Z:\SQLBackup" -CleanupTime 72
    
	.EXAMPLE
        This will drop and then recreate the Ola Hallengren's Solution objects
        Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -BackupLocation "Z:\SQLBackup" -CleanupTime 72 -ReplaceExisting 1
        The cleanup script will drop and recreate:
            - TABLE [dbo].[CommandLog]
            - STORED PROCEDURE [dbo].[CommandExecute]
            - STORED PROCEDURE [dbo].[DatabaseBackup]
            - STORED PROCEDURE [dbo].[DatabaseIntegrityCheck]
            - STORED PROCEDURE [dbo].[IndexOptimize]

        The follwing SQL Agent jobs will be deleted:
            - 'Output File Cleanup'
            - 'IndexOptimize - USER_DATABASES'
            - 'sp_delete_backuphistory'
            - 'DatabaseBackup - USER_DATABASES - LOG'
            - 'DatabaseBackup - SYSTEM_DATABASES - FULL'
            - 'DatabaseBackup - USER_DATABASES - FULL'
            - 'sp_purge_jobhistory'
            - 'DatabaseIntegrityCheck - SYSTEM_DATABASES'
            - 'CommandLog Cleanup'
            - 'DatabaseIntegrityCheck - USER_DATABASES'
            - 'DatabaseBackup - USER_DATABASES - DIFF'

    #>
	
	
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias('ServerInstance', 'SqlServer')]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[object]$Database = "master",
		[string]$BackupLocation,
		[int]$CleanupTime,
		[string]$OutputFileDirectory,
		[switch]$ReplaceExisting,
		[switch]$Silent
	)
	
	process {
		
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			if ((Test-Bound -Parameter BackupLocation -Not)) {
				$BackupLocation = (Get-DbaDefaultPath -SqlInstance $server).Backup
			}
			
			Write-Message -Level Output -Message "Ola Hallengren's solution will be installed on database: $Database"
			
			$db = $server.Databases[$Database]
			
			if ($ReplaceExisting) {
				Write-Message -Level Output -Message "If Ola Hallengren's scripts are found, we will drop and recreate them!"
			}
			
			$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
			$shell = New-Object -ComObject Shell.Application
			$zipfile = "$temp\ola.zip"
			
			# Start the download
			$url = "https://github.com/olahallengren/sql-server-maintenance-solution/archive/master.zip"
			try {
				$job = Start-BitsTransfer -Source $url -DisplayName Ola -Destination $zipfile -ErrorAction Stop
			}
			catch {
				Stop-Function -Message "You need to re-run the script, there is a problem with the proxy or the download link has changed." -ErrorRecord $_
			}
			
			# Unblock if there's a block
			Unblock-File $zipfile -ErrorAction SilentlyContinue
			
			# internal if it doesn't exist			
			Expand-Archive -Path $zipfile -DestinationPath $temp -Force
			Remove-Item -Path $zipfile
			
			$path = "$temp\sql-server-maintenance-solution-master"
			$listOfFiles = Get-ChildItem -Filter "*.sql" -Path $path | Select-Object -ExpandProperty FullName
			
			# In which database we install
			if ($Database -ne 'master') {
				$findDB = 'USE [master]'
				$replaceDB = 'USE [' + $Database + ']'
				foreach ($file in $listOfFiles) {
					(Get-Content -Path $file -Raw).Replace($findDB, $replaceDB) | Set-Content -Path $file
				}
			}
			
			# Backup location
			if ($BackupLocation) {
				$findBKP = 'C:\Backup'
				$replaceBKP = $BackupLocation
				foreach ($file in $listOfFiles) {
					(Get-Content -Path $file -Raw).Replace($findBKP, $replaceBKP) | Set-Content -Path $file
				}
			}
			
			# CleanupTime
			if ($CleanupTime -ne 0) {
				$findCleanupTime = 'SET @CleanupTime         = NULL'
				$replaceCleanupTime = 'SET @CleanupTime         = ' + $CleanupTime
				foreach ($file in $listOfFiles) {
					(Get-Content -Path $file -Raw).Replace($findCleanupTime, $replaceCleanupTime) | Set-Content -Path $file
				}
			}
			
			# OutputFileDirectory
			if ($OutputFileDirectory.Length -gt 0) {
				$findOutputFileDirectory = 'SET @OutputFileDirectory = NULL'
				$replaceOutputFileDirectory = 'SET @OutputFileDirectory = N''' + $OutputFileDirectory + ''''
				foreach ($file in $listOfFiles) {
					(Get-Content -Path $file -Raw).Replace($findOutputFileDirectory, $replaceOutputFileDirectory) | Set-Content -Path $file
				}
				
			}
			
			$CleanupQuery = $null
			if ($ReplaceExisting) {
				[string]$CleanupQuery = $("
                            DROP TABLE [dbo].[CommandLog]
                            DROP PROCEDURE [dbo].[CommandExecute]
                            DROP PROCEDURE [dbo].[DatabaseBackup]
                            DROP PROCEDURE [dbo].[DatabaseIntegrityCheck]
                            DROP PROCEDURE [dbo].[IndexOptimize]
                            ")
				
				Write-Message -Level Output -Message "Dropping objects created by Ola's Maintenance Solution"
				$null = $db.Query($CleanupQuery)
				
				# Remove Ola's Jobs                     
				Write-Message -Level Output -Message "Removing existing SQL Agent Jobs created by Ola's Maintenance Solution"
				$jobs = Get-DbaAgentJob -SqlInstance $server | Where-Object Description -match "hallengren"
				if ($jobs) {
					$jobs | Remove-DbaAgentJob
				}
			}
			
			try {
				Write-Message -Level Output -Message "Installing on server $SqlInstance, database $Database"
				
				$procs = Get-DbaSqlModule -SqlInstance $server | where Name -in 'CommandExecute', 'DatabaseBackup', 'DatabaseIntegrityCheck', 'IndexOptimize'
				$table = Get-DbaTable -SqlInstance $server -Database $Database -Table CommandLog
				
				if ($null -ne $procs -or $null -ne $table) {
					Stop-Function -Message "The Maintenance Solution alredy exists in $Database on $instance. Use -ReplaceExisting to automatically drop and recreate."
					return	
				}
				
				foreach ($file in $listOfFiles) {
					$sql = [IO.File]::ReadAllText($file)
					try {
						foreach ($query in ($sql -Split "\nGO\b")) {
							$null = $db.Query($query)
						}
					}
					catch {
						Stop-Function -Message "Could not execute $file" -ErrorRecord $_ -Target $db
					}
				}
			}
			catch {
				Write-Message -Level Warning -Message "Could not execute $file in $Database on $instance" -ErrorRecord $_
			}
		}
	}
	
	end {
		$path = "$temp\sql-server-maintenance-solution-master"
		if ((Test-Path $path)) {
			Remove-Item -Path $temp\sql-server-maintenance-solution-master -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
}
