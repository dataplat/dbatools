function Get-DbaDbCompression {


    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        $results = @()
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance" -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SourceSqlCredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $dbs = $server.Databases | Where-Object IsAccessible

                if ($Database) {
                    $dbs = $dbs | Where-Object { $Database -contains $_.Name -and $_.IsSystemObject -eq 0 }
                }

                else {
                    $dbs = $dbs | Where-Object { $_.IsSystemObject -eq 0 }
                }

                if (Test-Bound "ExcludeDatabase") {
                    $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
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
                                $results += [pscustomobject]@{
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
                                }
                            }
                        }

                        foreach ($index in $obj.Indexes) {
                            foreach ($p in $obj.PhysicalPartitions) {
                                $results += [pscustomobject]@{
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
                                    SizeCurrent         = [dbasize]($index.SpaceUsed * 1024)
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
        return $results
    }
}