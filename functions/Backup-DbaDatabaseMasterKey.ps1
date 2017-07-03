Function Backup-DbaDatabaseMasterKey {
	<#
.SYNOPSIS
Backs up specified database master key

.DESCRIPTION
Backs up specified database master key

.PARAMETER SqlInstance
The target SQL Server instance

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER Database
Backup master key from specific database

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto populated from the server

.PARAMETER BackupDirectory
The directory to export the key. If no backup directory is specified, the default backup directory will be used.
	
.PARAMETER Password
The password to encrypt the exported key. This must be a securestring.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Certificate, Databases

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Backup-DbaDatabaseMasterKey -SqlInstance server1\sql2016

Prompts for export password, then logs into server1\sql2016 with windows credentials then backs up all database keys to the default backup directory
	
ComputerName : SERVER1
InstanceName : SQL2016
SqlInstance  : SERVER1\SQL2016
Database     : master
Filename     : E:\MSSQL13.SQL2016\MSSQL\Backup\server1$sql2016-master-20170614162311.key
Status       : Success

.EXAMPLE
Backup-DbaDatabaseMasterKey -SqlInstance Server1 -Database db1 -BackupDirectory \\nas\sqlbackups\keys

Logs into sql2016 with windows credentials then backs up db1's keys to the \\nas\sqlbackups\keys directory

#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[Security.SecureString]$Password,
		[string]$BackupDirectory,
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
			
			$databases = $server.Databases
			
			if ($Database) {
				$databases = $databases | Where-Object Name -In $Database
			}
			if ($ExcludeDatabase) {
				$databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
			}
			
			if (Was-bound -ParameterName BackupDirectory -Not) {
				$backupdirectory = $server.BackupDirectory
			}
			
			if (!$backupdirectory) {
				Stop-Function -Message "Backup directory discovery failed. Please expliticly specify -BackupDirectory" -Target $server -Continue
			}
			
			if (!(Test-DbaSqlPath -SqlInstance $server -Path $BackupDirectory)) {
				Stop-Function -Message "$instance cannot access $backupdirectory" -Target $server -InnerErrorRecord $_ -Continue
			}
			
			foreach ($db in $databases) {
								
				if (!$db.IsAccessible) {
					Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
					continue
				}
				
				$masterkey = $db.MasterKey
				
				if (!$masterkey) {
					Write-Message -Message "No master key exists in the $db database on $instance" -Target $db -Level Verbose
					continue
				}
				
				# If you pass a password param, then you will not be prompted for each database, but it wouldn't be a good idea to build in insecurity
				if (Was-bound -ParameterName Password -Not) {
					$password = Read-Host -AsSecureString -Prompt "You must enter Service Key password for $instance"
					$password2 = Read-Host -AsSecureString -Prompt "Type the password again"
					
					if (([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password))) -ne ([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password2)))) {
						Stop-Function -Message "Passwords do not match" -Continue
					}
				}
				
				$time = (Get-Date -Format yyyMMddHHmmss)
				$dbname = $db.name
				$BackupDirectory = $BackupDirectory.TrimEnd("\")
				$fileinstance = $instance.ToString().Replace('\','$')
				$filename = "$BackupDirectory\$fileinstance-$dbname-$time.key"
				
				try {
					$masterkey.export($filename, [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password)))
					$status = "Success"
				}
				catch {
					$status = "Failure"
					Write-Message -Level Warning -Message "Backup failure: $($_.Exception.InnerException)"
				}
				
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $server.NetName
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name Database -value $dbname
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name Filename -value $filename
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name Status -value $status
				
				Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, Filename, Status
			}
		}
	}
}