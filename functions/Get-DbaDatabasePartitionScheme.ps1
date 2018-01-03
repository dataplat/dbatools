function Get-DbaDatabasePartitionScheme {
    <#
.SYNOPSIS
Gets database Partition Schemes

.DESCRIPTION
Gets database Partition Schemes

.PARAMETER SqlInstance
The target SQL Server instance(s)

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER Database
To get users from specific database(s)

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto populated from the server

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Databases
Author: Klaas Vandenberghe ( @PowerDbaKlaas )

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaDatabasePartitionScheme -SqlInstance sql2016

Gets all database Partition Schemes

.EXAMPLE
Get-DbaDatabasePartitionScheme -SqlInstance Server1 -Database db1

Gets the Partition Schemes for the db1 database

.EXAMPLE
Get-DbaDatabasePartitionScheme -SqlInstance Server1 -ExcludeDatabase db1

Gets the Partition Schemes for all databases except db1

.EXAMPLE
'Sql1','Sql2/sqlexpress' | Get-DbaDatabasePartitionScheme

Gets the Partition Schemes for the databases on Sql1 and Sql2/sqlexpress

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch][Alias('Silent')]$EnableException
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

            $databases = $server.Databases | Where-Object IsAccessible

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

                $PartitionSchemes = $db.PartitionSchemes

                if (!$PartitionSchemes) {
                    Write-Message -Message "No Partition Schemes exist in the $db database on $instance" -Target $db -Level Verbose
                    continue
                }

                $PartitionSchemes | foreach {

                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, Database, Name, PartitionFunction
                }
            }
        }
    }
}