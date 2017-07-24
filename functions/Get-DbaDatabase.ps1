function Get-DbaDatabase {
    <#
		.SYNOPSIS
			Gets SQL Database information for each database that is present in the target instance(s) of SQL Server.

		.DESCRIPTION
			The Get-DbaDatabase command gets SQL database information for each database that is present in the target instance(s) of
			SQL Server. If the name of the database is provided, the command will return only the specific database information.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
			to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			PSCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Database
			The database(s) to process. If unspecified, all databases will be processed.

		.PARAMETER ExcludeDatabase
			The database(s) to exclude.

		.PARAMETER ExcludeAllUserDb
			Returns only databases that are not User Databases.
            This parameter cannot be used together with -ExcludeAllSystemDb.

		.PARAMETER ExcludeAllSystemDb
			Returns only databases that are not System Databases.
            This parameter cannot be used together with -ExcludeAllUserDb.

		.PARAMETER Status
			Returns SQL Server databases in the status(es) listed.
            Could include Emergency, Online, Offline, Recovering, Restoring, Standby or Suspect.	

		.PARAMETER Access
			Returns SQL Server databases that are Read Only or Read/Write.
            To collect both, don't use this parameter.

		.PARAMETER Owner
			Returns list of databases owned by the specified logins.

		.PARAMETER Encrypted
			Returns list of databases that have TDE enabled from the SQL Server instance(s) executed against.

		.PARAMETER RecoveryModel
			Returns list of databases in listed recovery models (Full, Simple or Bulk Logged).

		.PARAMETER NoFullBackup
			Returns databases without a full backup recorded by SQL Server. Will indicate those which only have CopyOnly full backups.

		.PARAMETER NoFullBackupSince
			DateTime value. Returns list of databases that haven't had a full backup since the passed in DateTime.

		.PARAMETER NoLogBackup
			Returns databases without a Log backup recorded by SQL Server. Will indicate those which only have CopyOnly Log backups.

		.PARAMETER NoLogBackupSince
			DateTime value. Returns list of databases that haven't had a Log backup since the passed in DateTime.

		.PARAMETER LastUsed
			Returns the Last used read and write Times for the Database using the sys.dm_db_index_usage_stats DMV which will show
			the information since the last restart of SQL

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Database
			Original Author: Garry Bargsley (@gbargsley | http://blog.garrybargsley.com)
            Author: Klaas Vandenberghe ( @PowerDbaKlaas )
            Author: Simone Bizzotto ( @niphlod )

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaDatabase

		.EXAMPLE
			Get-DbaDatabase -SqlInstance localhost

			Returns all databases on the local default SQL Server instance

		.EXAMPLE
			Get-DbaDatabase -SqlInstance localhost -ExcludeAllUserDb

			Returns only the system databases on the local default SQL Server instance

		.EXAMPLE
			Get-DbaDatabase -SqlInstance localhost -ExcludeAllSystemDb

			Returns only the user databases on the local default SQL Server instance

		.EXAMPLE
			'localhost','sql2016' | Get-DbaDatabase

			Returns databases on multiple instances piped into the function

		.EXAMPLE
			Get-DbaDatabase -SqlInstance SQL1\SQLExpress -RecoveryModel full,Simple

			Returns only the user databases in Full or Simple recovery model from SQL1\SQLExpress

		.EXAMPLE
			Get-DbaDatabase -SqlInstance SQL1\SQLExpress -Status Normal

			Returns only the user databases with status 'normal' from sql instance SQL1\SQLExpress
		.EXAMPLE
			Get-DbaDatabase -SqlInstance SQL1\SQLExpress -LastUsed

			Returns the databases from sql instance SQL1\SQLExpress including the last used information 
			from the sys.dm_db_index_usage_stats DMV

		.EXAMPLE
			Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -ExcludeDatabase model,master

			Returns all databases except master and model from sql instances SQL1\SQLExpress and SQL2

		.EXAMPLE
			Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -Encrypted

			Returns only encrypted databases from sql instances SQL1\SQLExpress and SQL2

		.EXAMPLE
			Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -Access ReadOnly

			Returns only read only databases from sql instances SQL1\SQLExpress and SQL2

		.EXAMPLE
			Get-DbaDatabase -SqlInstance SQL2,SQL3 -Database OneDB,OtherDB

			Returns databases 'OneDb' and 'OtherDB' from sql instances SQL2 and SQL3 if the databases exist on those instances
	#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	[OutputType([Microsoft.SqlServer.Management.Smo.Database[]])]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[Alias("SystemDbOnly", "NoUserDb")]
		[switch]$ExcludeAllUserDb,
		[Alias("UserDbOnly", "NoSystemDb")]
		[switch]$ExcludeAllSystemDb,
		[string[]]$Owner,
		[switch]$Encrypted,
		[ValidateSet('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect')]
		[string[]]$Status = @('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect'),
		[ValidateSet('ReadOnly', 'ReadWrite')]
		[string]$Access,
		[ValidateSet('Full', 'Simple', 'BulkLogged')]
		[string[]]$RecoveryModel = @('Full', 'Simple', 'BulkLogged'),
		[switch]$NoFullBackup,
		[datetime]$NoFullBackupSince,
		[switch]$NoLogBackup,
		[datetime]$NoLogBackupSince,
		[switch]$Silent,
		[switch]$LastUsed
	)
	
	begin {
		
		if ($ExcludeAllUserDb -and $ExcludeAllSystemDb) {
			Stop-Function -Message "You cannot specify both ExcludeAllUserDb and ExcludeAllSystemDb" -Continue -Silent $Silent
		}
		
	}
	process {
		if (Test-FunctionInterrupt) { return }
		
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			if (!$LastUsed) {
				$dblastused = $null
			}
			else {
				## Get last used information from the DMV
				$querylastused = "WITH agg AS
				(
				  SELECT 
				       max(last_user_seek) last_user_seek,
				       max(last_user_scan) last_user_scan,
				       max(last_user_lookup) last_user_lookup,
				       max(last_user_update) last_user_update,
				       sd.name dbname
				   FROM
				       sys.dm_db_index_usage_stats, master..sysdatabases sd
				   WHERE
				     database_id = sd.dbid AND database_id > 4
					  group by sd.name 
				)
				SELECT 
				   dbname,
				   last_read = MAX(last_read),
				   last_write = MAX(last_write)
				FROM
				(
				   SELECT dbname, last_user_seek, NULL FROM agg
				   UNION ALL
				   SELECT dbname, last_user_scan, NULL FROM agg
				   UNION ALL
				   SELECT dbname, last_user_lookup, NULL FROM agg
				   UNION ALL
				   SELECT dbname, NULL, last_user_update FROM agg
				) AS x (dbname, last_read, last_write)
				GROUP BY
				   dbname
				ORDER BY 1;"
				# put a function around this to enable Pester Testing and also to ease any future changes
				function Invoke-QueryDBlastUsed {
					$server.Query($querylastused)
				}
				$dblastused = Invoke-QueryDBlastUsed
			}
			
			if ($ExcludeAllUserDb) {
				$DBType = @($true)
			}
			elseif ($ExcludeAllSystemDb) {
				$DBType = @($false)
			}
			else {
				$DBType = @($false, $true)
			}
			
			$Readonly = switch ($Access) { 'Readonly' { @($true) } 'ReadWrite' { @($false) }
				default { @($true, $false) } }
			$Encrypt = switch (Test-Bound $Encrypted) { $true { @($true) }
				default { @($true, $false, $null) } }
			
			$inputobject = $server.Databases |
			Where-Object {
				($_.Name -in $Database -or !$Database) -and
				($_.Name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
				($_.Owner -in $Owner -or !$Owner) -and
				$_.ReadOnly -in $Readonly -and
				$_.IsSystemObject -in $DBType -and
				((Compare-Object @($_.Status.tostring().split(',').trim()) $Status -ExcludeDifferent -IncludeEqual).inputobject.count -ge 1 -or !$status) -and
				$_.RecoveryModel -in $RecoveryModel -and
				$_.EncryptionEnabled -in $Encrypt
			}
			
			if ($NoFullBackup -or $NoFullBackupSince) {
				$dabs = (Get-DbaBackupHistory -SqlInstance $server -LastFull -IgnoreCopyOnly)
				if ($null -ne $NoFullBackupSince) {
					$dabsWithinScope = ($dabs | Where-Object End -lt $NoFullBackupSince)
					
					$inputobject = $inputobject | Where-Object { $_.Name -in $dabsWithinScope.Database -and $_.Name -ne 'tempdb' }
				}
				else {
					$inputObject = $inputObject | Where-Object { $_.Name -notin $dabs.Database -and $_.Name -ne 'tempdb' }
				}
				
			}
			if ($NoLogBackup -or $NoLogBackupSince) {
				$dabs = (Get-DbaBackupHistory -SqlInstance $server -LastLog -IgnoreCopyOnly)
				if ($null -ne $NoLogBackupSince) {
					$dabsWithinScope = ($dabs | Where-Object End -lt $NoLogBackupSince)
					$inputobject = $inputobject |
					Where-Object { $_.Name -in $dabsWithinScope.Database -and $_.Name -ne 'tempdb' -and $_.RecoveryModel -ne 'Simple' }
				}
				else {
					$inputobject = $inputObject |
					Where-Object { $_.Name -notin $dabs.Database -and $_.Name -ne 'tempdb' -and $_.RecoveryModel -ne 'Simple' }
				}
			}
			
			$defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status', 'IsAccessible', 'RecoveryModel',
			'LogReuseWaitStatus', 'Size as SizeMB', 'CompatibilityLevel as Compatibility', 'Collation', 'Owner',
			'LastBackupDate as LastFullBackup', 'LastDifferentialBackupDate as LastDiffBackup',
			'LastLogBackupDate as LastLogBackup'
			
			if ($NoFullBackup -or $NoFullBackupSince -or $NoLogBackup -or $NoLogBackupSince) {
				$defaults += ('Notes')
			}
			if ($LastUsed) {
				# Add Last Used to the default view
				$defaults += ('LastRead as LastIndexRead', 'LastWrite as LastIndexWrite')
			}
			
			try {
				foreach ($db in $inputobject) {
					
					$Notes = $null
					if ($NoFullBackup -or $NoFullBackupSince) {
						if (@($db.EnumBackupSets()).count -eq @($db.EnumBackupSets() | Where-Object { $_.IsCopyOnly }).count -and (@($db.EnumBackupSets()).count -gt 0)) {
							$Notes = "Only CopyOnly backups"
						}
					}
					
					$lastusedinfo = $dblastused | Where-Object { $_.dbname -eq $db.name }
					Add-Member -Force -InputObject $db -MemberType NoteProperty BackupStatus -value $Notes
					Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -value $server.NetName
					Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
					Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
					Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastRead -value $lastusedinfo.last_read
					Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastWrite -value $lastusedinfo.last_write
					Select-DefaultView -InputObject $db -Property $defaults
				}
			}
			catch {
				Stop-Message -ErrorRecord $_ -Target $instance -Message "Failure. Collection may have been modified. If so, please use parens (Get-DbaDatabase ....) | when working with commands that modify the collection such as Remove-DbaDatabase" -Continue
			}
		}
	}
}