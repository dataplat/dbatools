function Get-DbaDbCompression {
    <#
        .SYNOPSIS
            Gets tables and indexes size and current compression settings.

        .DESCRIPTION
            This function gets the current size and compression for all objects in the specified database(s), if no database is specified it will return all objects in all user databases.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            The database(s) to process - this list is auto populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            The database(s) to exclude - this list is auto populated from the server.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Jess Pomfret (@jpomfret jesspomfret.com)
            Tags: Compression, Table, Database
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            Get-DbaDbCompression -SqlInstance localhost

            Returns objects size and current compression level for all user databases.

        .EXAMPLE
            Get-DbaDbCompression -SqlInstance localhost -Database TestDatabase

            Returns objects size and current compression level for objects within the TestDatabase database.

            .EXAMPLE
            Get-DbaDbCompression -SqlInstance localhost -ExcludeDatabase TestDatabases

            Returns objects size and current compression level for objects in all databases except the TestDatabase database.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance" -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -and $_.IsSystemObject -eq 0 }

                if ($Database) {
                    $dbs = $dbs | Where-Object { $_.Name -In $Database }
                }

                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $_.Name -NotIn $ExcludeDatabase }
                }
            }
            catch {
                Stop-Function -Message "Unable to gather list of databases for $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            foreach ($db in $dbs) {
                try {
                    foreach ($obj in $server.Databases[$($db.name)].Tables) {
                        if ($obj.HasHeapIndex) {
                            foreach ($p in $obj.PhysicalPartitions) {
                                [pscustomobject]@{
                                    ComputerName        = $server.NetName
                                    InstanceName        = $server.ServiceName
                                    SqlInstance         = $server.DomainInstanceName
                                    Database            = $db.Name
                                    Schema              = $obj.Schema
                                    TableName           = $obj.Name
                                    IndexName           = $null
                                    Partition           = $p.PartitionNumber
                                    IndexID             = 0
                                    IndexType           = "Heap"
                                    DataCompression     = $p.DataCompression
                                    SizeCurrent         = [dbasize]($obj.DataSpaceUsed * 1024)
                                    RowCount            = $obj.RowCount
                                }
                            }
                        }

                        foreach ($index in $obj.Indexes) {
                            foreach ($p in $index.PhysicalPartitions) {
                                [pscustomobject]@{
                                    ComputerName        = $server.NetName
                                    InstanceName        = $server.ServiceName
                                    SqlInstance         = $server.DomainInstanceName
                                    Database            = $db.Name
                                    Schema              = $obj.Schema
                                    TableName           = $obj.Name
                                    IndexName           = $index.Name
                                    Partition           = $p.PartitionNumber
                                    IndexID             = $index.ID
                                    IndexType           = $index.IndexType
                                    DataCompression     = $p.DataCompression
                                    SizeCurrent         = if($index.IndexType -eq "ClusteredIndex") { [dbasize]($obj.DataSpaceUsed * 1024) } else { [dbasize]($index.SpaceUsed * 1024) }
                                    RowCount            = $p.RowCount
                                }
                            }
                        }

                    }
                }
                catch {
                    Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }

            }
        }
    }
}