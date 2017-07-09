Function Get-DbaDatabasePartitionFunction {
	<#
.SYNOPSIS
Gets database Partition Functions

.DESCRIPTION
Gets database Partition Functions

.PARAMETER SqlInstance
The target SQL Server instance(s)

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER Database
To get users from specific database(s)

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto populated from the server

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Databases
Author: Klaas Vandenberghe ( @PowerDbaKlaas )

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaDatabasePartitionFunction -SqlInstance sql2016

Gets all database Partition Functions

.EXAMPLE
Get-DbaDatabasePartitionFunction -SqlInstance Server1 -Database db1

Gets the Partition Functions for the db1 database

.EXAMPLE
Get-DbaDatabasePartitionFunction -SqlInstance Server1 -ExcludeDatabase db1

Gets the Partition Functions for all databases except db1

.EXAMPLE
'Sql1','Sql2/sqlexpress' | Get-DbaDatabasePartitionFunction

Gets the Partition Functions for the databases on Sql1 and Sql2/sqlexpress

#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
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
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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

				$partitionfunctions = $db.partitionfunctions

				if (!$partitionfunctions) {
					Write-Message -Message "No Partition Functions exist in the $db database on $instance" -Target $db -Level Verbose
					continue
				}

                $partitionfunctions | foreach {

				Add-Member -InputObject $_ -MemberType NoteProperty -Name ComputerName -value $server.NetName
				Add-Member -InputObject $_ -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
				Add-Member -InputObject $_ -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
				Add-Member -InputObject $_ -MemberType NoteProperty -Name Database -value $db.Name

				Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, Name, NumberOfPartitions
                }
			}
		}
	}
}