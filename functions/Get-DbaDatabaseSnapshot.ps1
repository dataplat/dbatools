#ValidationTags#FlowControl#
function Get-DbaDatabaseSnapshot {
    <#
    .SYNOPSIS
        Get database snapshots with details

    .DESCRIPTION
        Retrieves the list of database snapshot available, along with their base (the db they are the snapshot of) and creation time

    .PARAMETER SqlInstance
        The SQL Server that you're connecting to.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server as a different user

    .PARAMETER Database
        Return information for only specific databases

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER Snapshot
        Return information for only specific snapshots

    .PARAMETER ExcludeSnapshot
        The snapshot(s) to exclude - this list is auto-populated from the server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Snapshot
        Author: niphlod

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT


    .LINK
         https://dbatools.io/Get-DbaDatabaseSnapshot

    .EXAMPLE
        Get-DbaDatabaseSnapshot -SqlInstance sqlserver2014a

        Returns a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated

    .EXAMPLE
        Get-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

        Returns information for database snapshots having HR and Accounting as base dbs

    .EXAMPLE
        Get-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snapshot, Accounting_snapshot

        Returns information for database snapshots HR_snapshot and Accounting_snapshot

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
        [object[]]$Snapshot,
        [object[]]$ExcludeSnapshot,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $alldbq = @"
SELECT sn.name as Name, dt.name as DatabaseSnapshotBaseName, sn.create_date as CreateDate,
CASE WHEN sn.source_database_id IS NOT NULL THEN 1 ELSE 0 END as IsDatabaseSnapshot
FROM sys.databases sn
LEFT JOIN sys.databases dt
ON sn.source_database_id = dt.database_id
WHERE sn.state <> 6
"@
            $dbs = $server.Query($alldbq)
            #$dbs = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $dbs = $dbs | Where-Object { $Database -contains $_.DatabaseSnapshotBaseName }
            }
            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.DatabaseSnapshotBaseName }
            }
            if ($Snapshot) {
                $dbs = $dbs | Where-Object { $Snapshot -contains $_.Name }
            }
            if (!$Snapshot -and !$Database) {
                $dbs = $dbs | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name
            }
            if ($ExcludeSnapshot) {
                $dbs = $dbs | Where-Object { $ExcludeSnapshot -notcontains $_.Name }
            }

            foreach ($db in $dbs) {
                $object = [PSCustomObject]@{
                    ComputerName    = $server.NetName
                    InstanceName    = $server.ServiceName
                    SqlInstance     = $server.DomainInstanceName
                    Database        = $db.Name
                    SnapshotOf      = $db.DatabaseSnapshotBaseName
                    SizeMB          = [Math]::Round($db.Size, 2) ##FIXME, should use the stats for sparse files
                    DatabaseCreated = [dbadatetime]$db.createDate
                    SnapshotDb      = $server.Databases[$db.Name]
                }

                Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, Database, SnapshotOf, SizeMB, DatabaseCreated
            }
        }
    }
}

