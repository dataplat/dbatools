Function Get-DbaDatabaseMasterKey {
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
Get-DbaDatabaseMasterKey -SqlInstance sql2016

Gets all master database keys

.EXAMPLE
Get-DbaDatabaseMasterKey -SqlInstance Server1 -Database db1

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

				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $server.NetName
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
				Add-Member -InputObject $masterkey -MemberType NoteProperty -Name Database -value $db.Name

				Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, IsEncryptedByServer
			}
		}
	}
}