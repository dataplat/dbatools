function Get-DbaDbQueryStoreOptions {
    <#
.SYNOPSIS
Get the Query Store configuration for Query Store enabled databases.

.DESCRIPTION
Retrieves and returns the Query Store configuration for every database that has the Query Store feature enabled.

.OUTPUTS
Microsoft.SqlServer.Management.Smo.QueryStoreOptions

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
SqlCredential object used to connect to the SQL Server as a different user.

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: QueryStore
Author: Enrico van de Laar ( @evdlaar )
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaQueryStoreOptions

.EXAMPLE
Get-DbaDbQueryStoreOptions -SqlInstance ServerA\sql

Returns Query Store configuration settings for every database on the ServerA\sql instance.

.EXAMPLE
Get-DbaDbQueryStoreOptions -SqlInstance ServerA\sql | Where-Object {$_.ActualState -eq "ReadWrite"}

Returns the Query Store configuration for all databases on ServerA\sql where the Query Store feature is in Read/Write mode.

.EXAMPLE
Get-DbaDbQueryStoreOptions -SqlInstance localhost | format-table -AutoSize -Wrap

Returns Query Store configuration settings for every database on the ServerA\sql instance inside a table format.

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch][Alias('Silent')]$EnableException
    )
    begin {
        $ExcludeDatabase += 'master', 'tempdb'
    }
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Write-Message -Level Warning -Message "Can't connect to $instance. Moving on."
                continue
            }

            if ($server.VersionMajor -lt 13) {
                Write-Message -Level Warning -Message "The SQL Server Instance ($instance) has a lower SQL Server version than SQL Server 2016. Skipping server."
                continue
            }

            # We have to exclude all the system databases since they cannot have the Query Store feature enabled
            $dbs = Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -ExcludeDatabase $ExcludeDatabase -Database $Database | Where-Object IsAccessible

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.Name) on $instance"
                $QSO = $db.QueryStoreOptions

                Add-Member -Force -InputObject $QSO -MemberType NoteProperty -Name ComputerName -value $server.NetName
                Add-Member -Force -InputObject $QSO -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $QSO -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $QSO -MemberType NoteProperty Database -value $db.Name
                Select-DefaultView -InputObject $QSO -Property ComputerName, InstanceName, SqlInstance, Database, ActualState, DataFlushIntervalInSeconds, StatisticsCollectionIntervalInMinutes, MaxStorageSizeInMB, CurrentStorageSizeInMB, QueryCaptureMode, SizeBasedCleanupMode, StaleQueryThresholdInDays
            }
        }
    }
}