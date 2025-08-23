function Get-DbaDbCompression {
    <#
    .SYNOPSIS
        Retrieves compression settings, sizes, and row counts for tables and indexes across SQL Server databases.

    .DESCRIPTION
        This function analyzes data compression usage across your SQL Server databases by examining tables, indexes, and their physical partitions. It returns detailed information including current compression type (None, Row, Page, Columnstore), space usage, and row counts for each object. This is essential for compression optimization analysis, identifying candidates for compression to save storage space, and generating compliance reports on compression usage across your database environment.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for compression information. Accepts multiple database names as an array.
        Use this when you want to focus compression analysis on specific databases rather than scanning all user databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies which databases to skip during compression analysis. Accepts multiple database names as an array.
        Use this to exclude system databases, maintenance databases, or other databases you don't want included in compression reporting.

    .PARAMETER Table
        Specifies which tables to analyze for compression information. Accepts multiple table names as an array.
        Use this when you need compression details for specific tables rather than all tables in the target databases, particularly useful for large databases where you want to focus on specific objects.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Compression, Table, Database
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbCompression

    .EXAMPLE
        PS C:\> Get-DbaDbCompression -SqlInstance localhost

        Returns objects size and current compression level for all user databases.

    .EXAMPLE
        PS C:\> Get-DbaDbCompression -SqlInstance localhost -Database TestDatabase

        Returns objects size and current compression level for objects within the TestDatabase database.

    .EXAMPLE
        PS C:\> Get-DbaDbCompression -SqlInstance localhost -ExcludeDatabase TestDatabases

        Returns objects size and current compression level for objects in all databases except the TestDatabase database.

    .EXAMPLE
        PS C:\> Get-DbaDbCompression -SqlInstance localhost -ExcludeDatabase TestDatabases -Table table1, table2

        Returns objects size and current compression level for table1 and table2 in all databases except the TestDatabase database.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Table,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -and $_.IsSystemObject -eq 0 }

                if ($Database) {
                    $dbs = $dbs | Where-Object { $_.Name -In $Database }
                }

                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $_.Name -NotIn $ExcludeDatabase }
                }
            } catch {
                Stop-Function -Message "Unable to gather list of databases for $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            foreach ($db in $dbs) {
                try {
                    $tables = $server.Databases[$($db.name)].Tables

                    if ($Table) {
                        $tables = $tables | Where-Object Name -in $Table
                    }

                    foreach ($obj in $tables) {
                        if ($obj.HasHeapIndex) {
                            foreach ($p in $obj.PhysicalPartitions) {
                                [PSCustomObject]@{
                                    ComputerName    = $server.ComputerName
                                    InstanceName    = $server.ServiceName
                                    SqlInstance     = $server.DomainInstanceName
                                    Database        = $db.Name
                                    DatabaseId      = $db.Id
                                    Schema          = $obj.Schema
                                    TableName       = $obj.Name
                                    IndexName       = $null
                                    Partition       = $p.PartitionNumber
                                    IndexID         = 0
                                    IndexType       = "Heap"
                                    DataCompression = $p.DataCompression
                                    SizeCurrent     = [dbasize]($obj.DataSpaceUsed * 1024)
                                    RowCount        = $obj.RowCount
                                }
                            }
                        }

                        foreach ($index in $obj.Indexes) {
                            foreach ($p in $index.PhysicalPartitions) {
                                [PSCustomObject]@{
                                    ComputerName    = $server.ComputerName
                                    InstanceName    = $server.ServiceName
                                    SqlInstance     = $server.DomainInstanceName
                                    Database        = $db.Name
                                    DatabaseId      = $db.Id
                                    Schema          = $obj.Schema
                                    TableName       = $obj.Name
                                    IndexName       = $index.Name
                                    Partition       = $p.PartitionNumber
                                    IndexID         = $index.ID
                                    IndexType       = $index.IndexType
                                    DataCompression = $p.DataCompression
                                    SizeCurrent     = if ($index.IndexType -eq "ClusteredIndex") { [dbasize]($obj.DataSpaceUsed * 1024) } else { [dbasize]($index.SpaceUsed * 1024) }
                                    RowCount        = $p.RowCount
                                }
                            }
                        }

                    }
                } catch {
                    Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}