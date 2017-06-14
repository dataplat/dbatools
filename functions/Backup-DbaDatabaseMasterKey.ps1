Function Backup-DbaDatabaseMasterKey {
	<#
.SYNOPSIS
Gets specified database master key

.DESCRIPTION
Gets specified database master key

.PARAMETER SqlInstance
The target SQL Server instance

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER Database
Get master key from specific database

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto populated from the server

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
Backup-DbaDatabaseMasterKey -SqlInstance sql2016

Gets all master database keys

.EXAMPLE
Backup-DbaDatabaseMasterKey -SqlInstance Server1 -Database db1

Gets the master key for the db1 database

#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
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
				Stop-Function -Message "Failed to connect to: $instance" -Target $instance -InnerErrorRecord $_ -Continue
			}
			
			$databases = $server.Databases
			
			if ($Database) {
				$databases = $databases | Where-Object Name -In $Database
			}
			if ($ExcludeDatabase) {
				$databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
			}
			
			if (!(Test-Dbapath -SqlInstance $server -Path $BackupDirectory)) {
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
				
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $server.NetName
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name Database -value $db.Name
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name BackupDirectory -value $backuppath
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name Filename -value $filename
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name Status -value $status
				
				Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, IsEncryptedByServer
			}
		}
	}
}