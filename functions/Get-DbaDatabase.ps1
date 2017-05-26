function Get-DbaDatabase {
	<#
		.SYNOPSIS
			Gets SQL Database information for each database that is present in the target instance(s) of SQL Server.

		.DESCRIPTION
			The Get-DbaDatabase command gets SQL database information for each database that is present in the target instance(s) of
			SQL Server. If the name of the database is provided, the command will return only the specific database information.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
			to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			PSCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Database
			The database(s) to process. If unspecified, all databases will be processed.

		.PARAMETER ExcludeDatabase
			The database(s) to exclude.

		.PARAMETER NoUserDb
			Returns all SQL Server System databases from the SQL Server instance(s) executed against.

		.PARAMETER NoSystemDb
			Returns SQL Server user databases from the SQL Server instance(s) executed against.

		.PARAMETER Status
			Returns SQL Server databases in the status passed to the function.  Could include Emergency, Online, Offline, Recovering, Restoring, Standby or Suspect
			statuses of databases from the SQL Server instance(s) executed against.

		.PARAMETER Access
			Returns SQL Server databases that are Read Only or all other Online databases from the SQL Server intance(s) executed against.

		.PARAMETER Owner
			Returns list of SQL Server databases owned by the specified logins

		.PARAMETER Encrypted
			Returns list of SQL Server databases that have TDE enabled from the SQL Server instance(s) executed against.

		.PARAMETER RecoveryModel
			Returns list of SQL Server databases in Full, Simple or Bulk Logged recovery models from the SQL Server instance(s) executed against.

		.PARAMETER NoFullBackup
			Returns databases without a full backup recorded by SQL Server. Will indicate those which only have CopyOnly full backups

		.PARAMETER NoFullBackupSince
			DateTime value. Returns list of SQL Server databases that haven't had a full backup since the passed iin DateTime

		.PARAMETER NoLogBackup
			Returns databases without a Log backup recorded by SQL Server. Will indicate those which only have CopyOnly Log backups

		.PARAMETER NoLogBackupSince
			DateTime value. Returns list of SQL Server databases that haven't had a Log backup since the passed iin DateTime

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Database
			Original Author: Garry Bargsley (@gbargsley | http://blog.garrybargsley.com)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaDatabase

		.EXAMPLE
			Get-DbaDatabase -SqlInstance localhost

			Returns all databases on the local default SQL Server instance

		.EXAMPLE
			Get-DbaDatabase -SqlInstance localhost -NoUserDb

			Returns only the system databases on the local default SQL Server instance

		.EXAMPLE
			Get-DbaDatabase -SqlInstance localhost -NoSystemDb

			Returns only the user databases on the local default SQL Server instance

		.EXAMPLE
			'localhost','sql2016' | Get-DbaDatabase

			Returns databases on multiple instances piped into the function
	#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[Alias("SystemDbOnly")]
		[parameter(ParameterSetName = "NoUserDb")]
		[switch]$NoUserDb,
		[Alias("UserDbOnly")]
		[parameter(ParameterSetName = "NoSystemDb")]
		[switch]$NoSystemDb,
		[parameter(ParameterSetName = "DbBackuOwner")]
		[string[]]$Owner,
		[parameter(ParameterSetName = "Encrypted")]
		[switch]$Encrypted,
		[parameter(ParameterSetName = "Status")]
		[ValidateSet('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect')]
		[string[]]$Status,
		[parameter(ParameterSetName = "Access")]
		[ValidateSet('ReadOnly', 'ReadWrite')]
		[string]$Access,
		[parameter(ParameterSetName = "RecoveryModel")]
		[ValidateSet('Full', 'Simple', 'BulkLogged')]
		[string]$RecoveryModel,
		[switch]$NoFullBackup,
		[datetime]$NoFullBackupSince,
		[switch]$NoLogBackup,
		[datetime]$NoLogBackupSince,
		[switch]$Silent
	)

	begin {

		if ($NoUserDb -and $NoSystemDb) {
			Stop-Function -Message "You cannot specify both NoUserDb and NoSystemDb" -Continue -Silent $Silent
		}

		if ($status.count -gt 0) {
			foreach ($state in $status) {
				if ($state -notin ('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect')) {
					Stop-Function -Message "$state is not a valid status ('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect')" -Continue -Silent $Silent
				}

			}
		}
	}
	process {
		if (Test-FunctionInterrupt) { return }

		foreach ($instance in $SqlInstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -ErrorRecord $_ -Target $instance -Continue -Silent $Silent
			}

			if ($NoUserDb) {
				$inputobject = $server.Databases | Where-Object IsSystemObject
			}

			if ($NoSystemDb) {
				$inputobject = $server.Databases | Where-Object IsSystemObject -eq $false
			}

			if ($Database) {
				$inputobject = $server.Databases | Where-Object Name -in $Database
			}

			if ($status) {
				$StatusInput = @()
				foreach ($state in $status) {
					$StatusInput += $server.Databases | Where-Object { ($_.Status -split ', ') -contains $state }
				}
				$inputobject = $StatusInput | Select-object -unique
			}

			if ($Owner) {
				$inputobject = $server.Databases | Where-Object Owner -in $Owner
			}

			switch ($Access) {
				"ReadOnly" { $inputobject = $server.Databases | Where-Object ReadOnly }
				"ReadWrite" { $inputobject = $server.Databases | Where-Object ReadOnly -eq $false }
			}

			if ($Encrypted) {
				$inputobject = $server.Databases | Where-Object EncryptionEnabled
			}

			if ($RecoveryModel) {
				$inputobject = $server.Databases | Where-Object RecoveryModel -eq $RecoveryModel
			}

			# I forgot the pretty way to do this
			if (!$NoUserDb -and !$NoSystemDb -and !$database -and !$status -and !$Owner -and !$Access -and !$Encrypted -and !$RecoveryModel) {
				$inputobject = $server.Databases
			}

			if ($ExcludeDatabase) {
				$inputobject = $inputobject | Where-Object Name -notin $ExcludeDatabase
			}

			if ($NoFullBackup -or $NoFullBackupSince) {
				if ($NoFullBackup) {
					$dabs = (Get-DbaBackuphistory -SqlInstance $server -LastFull -IgnoreCopyOnly).Database
				}
				else {
					$dabs = (Get-DbaBackuphistory -SqlInstance $server -LastFull -IgnoreCopyOnly -Since $NoFullBackupSince).Database
				}
				$inputobject = $inputObject | where-object { $_.name -notin $dabs -and $_.name -ne 'tempdb' }
			}
			if ($NoLogBackup -or $NoLogBackupSince) {
				if ($NoLogBackup) {
					$dabs = (Get-DbaBackuphistory -SqlInstance $server -LastLog -IgnoreCopyOnly).Database
				}
				else {
					$dabs = (Get-DbaBackuphistory -SqlInstance $server -LastLog -IgnoreCopyOnly -Since $NoLogBackupSince).Database
				}
				$inputobject = $inputObject | where-object { $_.name -notin $dabs -and $_.name -ne 'tempdb' -and $_.RecoveryModel -ne 'simple' }
			}

			if ($null -ne $NoFullBackupSince) {
				$inputobject = $inputobject | Where-Object LastBackupdate -lt $NoFullBackupSince
			}
			elseif ($null -ne $NoLogBackupSince) {
				$inputobject = $inputobject | Where-Object LastBackupdate -lt $NoLogBackupSince
			}
			$defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status', 'RecoveryModel', 'Size as SizeMB', 'CompatibilityLevel as Compatibility', 'Collation', 'Owner', 'LastBackupDate as LastFullBackup', 'LastDifferentialBackupDate as LastDiffBackup', 'LastLogBackupDate as LastLogBackup'

			if ($NoFullBackup -or $NoFullBackupSince -or $NoLogBackup -or $NoLogBackupSince) {
				$defaults += ('Notes')
			}
			foreach ($db in $inputobject) {

				$Notes = $null
				if ($NoFullBackup -or $NoFullBackupSince) {
					if (@($db.EnumBackupSets()).count -eq @($db.EnumBackupSets() | Where-Object { $_.IsCopyOnly }).count -and (@($db.EnumBackupSets()).count -gt 0)) {
						$Notes = "Only CopyOnly backups"
					}
				}
				Add-Member -InputObject $db -MemberType NoteProperty BackupStatus -value $Notes

				Add-Member -InputObject $db -MemberType NoteProperty -Name ComputerName -value $server.NetName
				Add-Member -InputObject $db -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
				Add-Member -InputObject $db -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
				Select-DefaultView -InputObject $db -Property $defaults

			}
		}
	}
}

