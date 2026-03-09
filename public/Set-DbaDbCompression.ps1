function Set-DbaDbCompression {
    <#
    .SYNOPSIS
        Applies data compression to SQL Server tables and indexes to reduce storage space and improve performance.

    .DESCRIPTION
        Compresses tables, indexes, and heaps across one or more databases using Row, Page, or intelligent recommendations based on Microsoft's Tiger Team compression analysis. Automatically handles the complex process of analyzing usage patterns, applying appropriate compression types, and rebuilding objects online when possible. Saves significant storage space, reduces backup sizes, and improves I/O performance without requiring manual compression analysis for each object. Particularly valuable for large production databases where storage costs and backup windows are concerns.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to apply compression to. Accepts wildcard patterns and multiple database names.
        When omitted, all non-system databases on the instance will be processed. Use this to target specific databases when you don't want to compress everything.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during the compression operation. Accepts wildcard patterns and multiple database names.
        Use this when you want to compress most databases but exclude specific ones like databases under maintenance or with special requirements.

    .PARAMETER Table
        Specifies which tables to compress within the selected databases. Accepts multiple table names and works with wildcard patterns.
        When omitted, all eligible tables in the database will be processed. Use this to target specific large tables or avoid compressing certain tables.

    .PARAMETER CompressionType
        Specifies the type of compression to apply: Recommended, Page, Row, or None. Default is 'Recommended' which analyzes each object and applies the optimal compression type.
        Use 'Page' or 'Row' to force all objects to the same compression level, or 'None' to remove compression. Recommended is best for mixed workloads where different objects benefit from different compression types.

    .PARAMETER MaxRunTime
        Sets a time limit in minutes for the compression operation to prevent it from running indefinitely. When the time limit is reached, the function stops processing additional objects.
        Use this during business hours to ensure the operation completes within a maintenance window. A value of 0 (default) means no time limit.

    .PARAMETER PercentCompression
        Sets the minimum space savings threshold (as a percentage) required before an object will be compressed. Only objects that would achieve this level of savings or higher are processed.
        Use this to focus compression efforts on objects that will provide the most benefit. For example, setting this to 25 will only compress objects that would save at least 25% of their current space.

    .PARAMETER ForceOfflineRebuilds
        Forces compression operations to use offline rebuilds instead of the default online rebuilds when possible. Online rebuilds keep tables accessible during compression but use more resources.
        Use this switch when you need to minimize resource usage during compression or when experiencing issues with online operations. Offline rebuilds will make tables unavailable during the compression process.

    .PARAMETER InputObject
        Accepts compression recommendations from Test-DbaDbCompression and applies those specific recommendations instead of running a new analysis.
        Use this when you want to review compression recommendations first, then apply only the ones you approve of. This approach gives you more control over which objects get compressed.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Compression, Table, Database
        Author: Jason Squires (@js_0505), jstexasdba@gmail.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbCompression

    .OUTPUTS
        PSCustomObject

        Returns one object per partition for each table or index that was compressed. When using Recommended compression mode, returns the original compression analysis object with an additional AlreadyProcessed property indicating whether the recommendation was applied.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name
        - Schema: The schema name containing the table
        - TableName: The name of the table
        - IndexName: The name of the index; null for heap partitions, contains index name for indexed partitions
        - Partition: The partition number (1-based, or 1 for non-partitioned objects)
        - IndexID: The index ID number - 0 for heaps, greater than 0 for indexes
        - IndexType: The type of index structure (Heap, ClusteredIndex, or other SMO index type values)
        - CompressionTypeRecommendation: The compression type that was applied (ROW, PAGE, or NONE in uppercase)
        - AlreadyProcessed: A flag indicating if the object was successfully processed (True or False as string)
        - PercentScan: Placeholder property from Test-DbaDbCompression analysis (always null in output)
        - PercentUpdate: Placeholder property from Test-DbaDbCompression analysis (always null in output)
        - RowEstimatePercentOriginal: Placeholder property from Test-DbaDbCompression analysis (always null in output)
        - PageEstimatePercentOriginal: Placeholder property from Test-DbaDbCompression analysis (always null in output)
        - SizeCurrent: Placeholder property from Test-DbaDbCompression analysis (always null in output)
        - SizeRequested: Placeholder property from Test-DbaDbCompression analysis (always null in output)
        - PercentCompression: Placeholder property from Test-DbaDbCompression analysis (always null in output)

        When using CompressionType parameter (Row, Page, or None), returns objects for each partition that was compressed.
        When using CompressionType Recommended (default), returns objects from Test-DbaDbCompression with the AlreadyProcessed property added.
        In Recommended mode, only objects with CompressionTypeRecommendation that is not 'NO_GAIN' or '?' and meets the PercentCompression threshold are output.

    .EXAMPLE
        PS C:\> Set-DbaDbCompression -SqlInstance localhost -MaxRunTime 60 -PercentCompression 25

        Set the compression run time to 60 minutes and will start the compression of tables/indexes that have a difference of 25% or higher between current and recommended.

    .EXAMPLE
        PS C:\> Set-DbaDbCompression -SqlInstance ServerA -Database DBName -CompressionType Page -Table table1, table2

        Utilizes Page compression for tables table1 and table2 in DBName on ServerA with no time limit.

    .EXAMPLE
        PS C:\> Set-DbaDbCompression -SqlInstance ServerA -Database DBName -PercentCompression 25 | Out-GridView

        Will compress tables/indexes within the specified database that would show any % improvement with compression and with no time limit. The results will be piped into a nicely formatted GridView.

    .EXAMPLE
        PS C:\> $testCompression = Test-DbaDbCompression -SqlInstance ServerA -Database DBName
        PS C:\> Set-DbaDbCompression -SqlInstance ServerA -Database DBName -InputObject $testCompression

        Gets the compression suggestions from Test-DbaDbCompression into a variable, this can then be reviewed and passed into Set-DbaDbCompression.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Set-DbaDbCompression -SqlInstance ServerA -ExcludeDatabase Database -SqlCredential $cred -MaxRunTime 60 -PercentCompression 25

        Set the compression run time to 60 minutes and will start the compression of tables/indexes for all databases except the specified excluded database. Only objects that have a difference of 25% or higher between current and recommended will be compressed.

    .EXAMPLE
        PS C:\> $servers = 'Server1','Server2'
        PS C:\> foreach ($svr in $servers) {
        >> Set-DbaDbCompression -SqlInstance $svr -MaxRunTime 60 -PercentCompression 25 | Export-Csv -Path C:\temp\CompressionAnalysisPAC.csv -Append
        >> }

        Set the compression run time to 60 minutes and will start the compression of tables/indexes across all listed servers that have a difference of 25% or higher between current and recommended. Output of command is exported to a csv.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Table,
        [ValidateSet("Recommended", "Page", "Row", "None")]
        [string]$CompressionType = "Recommended",
        [int]$MaxRunTime = 0,
        [int]$PercentCompression = 0,
        [switch]$ForceOfflineRebuilds,
        $InputObject,
        [switch]$EnableException
    )


    process {
        $starttime = Get-Date
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #The reason why we do this is because of SQL 2016 and they now allow for compression on standard edition.
            if ($server.EngineEdition -notmatch 'Enterprise' -and $server.VersionMajor -lt '13') {
                Stop-Function -Message "Only SQL Server Enterprise Edition supports compression on $server" -Target $server -Continue
            }
            $dbs = $server.Databases | Where-Object { $_.IsAccessible -and $_.IsSystemObject -eq 0 }
            if ($Database) {
                $dbs = $dbs | Where-Object { $_.Name -in $Database }
            }
            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object { $_.Name -NotIn $ExcludeDatabase }
            }
            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Querying $instance - $db"
                if ($db.Status -ne 'Normal') {
                    Write-Message -Level Warning -Message "$db has status $($db.Status) and will be skipped." -Target $db
                    continue
                }
                if ($db.CompatibilityLevel -lt 'Version100') {
                    Write-Message -Level Warning -Message "$db has a compatibility level lower than Version100 and will be skipped."
                    continue
                }
                $isOnlineRebuildSupported = $false
                # Loop on indexes to see if Rebuild Online is supported
                $onlineRebuildScanCompleted = $false
                foreach ($obj in $tables | Where-Object { !$_.IsMemoryOptimized -and !$_.HasSparseColumn }) {
                    if ($onlineRebuildScanCompleted) {
                        break
                    }
                    foreach ($index in $($obj.Indexes | Where-Object { !$_.IsMemoryOptimized -and $_.IndexType -notmatch 'Columnstore' })) {
                        if ($index.IsOnlineRebuildSupported -or $server.isAzure) {
                            $isOnlineRebuildSupported = $true
                            $onlineRebuildScanCompleted = $true
                            break
                        }
                    }
                }
                Write-Message -Level Verbose -Message "Are Online Rebuilds supported ? $isOnlineRebuildSupported"
                $CanDoOnlineOperation = $false
                if ($IsOnlineRebuildSupported -and !$ForceOfflineRebuilds) {
                    $CanDoOnlineOperation = $true
                    Write-Message -Level Verbose -Message "Using Online Rebuilds where possible"
                }

                if ($CompressionType -eq "Recommended") {
                    if (Test-Bound "InputObject") {
                        Write-Message -Level Verbose -Message "Using passed in compression suggestions"
                        $compressionSuggestion = $InputObject | Where-Object { $_.Database -eq $db.Name }
                    } else {
                        if ($Pscmdlet.ShouldProcess($db, "Testing database for compression suggestions on $instance")) {
                            try {
                                $compressionSuggestion = Test-DbaDbCompression -SqlInstance $server -Database $db.Name -Table $Table -EnableException
                            } catch {
                                Stop-Function -Message "Unable to test database compression suggestions for $instance - $db" -Target $db -ErrorRecord $_ -Continue
                            }
                        }
                    }

                    if ($Pscmdlet.ShouldProcess($db, "Applying suggested compression using results from Test-DbaDbCompression")) {
                        $objects = $compressionSuggestion | Select-Object *, @{l = 'AlreadyProcessed'; e = { "False" } }
                        foreach ($obj in ($objects | Where-Object { $_.CompressionTypeRecommendation -notin @('NO_GAIN', '?') -and $_.PercentCompression -ge $PercentCompression } | Sort-Object PercentCompression -Descending)) {
                            if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                                Write-Message -Level Warning -Message "Reached max run time of $MaxRunTime"
                                break
                            }
                            if ($obj.indexId -le 1) {
                                ##heaps and clustered indexes
                                Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName)"
                                try {
                                    ($server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $obj.Partition }).DataCompression = $obj.CompressionTypeRecommendation
                                    $server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].OnlineHeapOperation = $CanDoOnlineOperation
                                    $server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Rebuild()
                                } catch {
                                    Stop-Function -Message "Compression failed for $instance - $db - table $($obj.Schema).$($obj.TableName) - partition $($obj.Partition)" -Target $db -ErrorRecord $_ -Continue
                                }
                            } else {
                                ##nonclustered indexes
                                Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName).$($obj.IndexName)"
                                try {
                                    $underlyingObj = $server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Indexes[$obj.IndexName]
                                    ($underlyingObj.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $obj.Partition }).DataCompression = $obj.CompressionTypeRecommendation
                                    $underlyingObj.OnlineIndexOperation = $CanDoOnlineOperation
                                    $underlyingObj.Rebuild()
                                } catch {
                                    Stop-Function -Message "Compression failed for $instance - $db - table $($obj.Schema).$($obj.TableName) - index $($obj.IndexName) - partition $($obj.Partition)" -Target $db -ErrorRecord $_ -Continue
                                }
                            }
                            $obj.AlreadyProcessed = "True"
                            $obj
                        }
                    }
                } else {
                    if ($Pscmdlet.ShouldProcess($db, "Applying $CompressionType compression")) {
                        $tables = $server.Databases[$($db.name)].Tables
                        if ($Table) {
                            $tables = $tables | Where-Object Name -in $Table
                        }

                        foreach ($obj in $tables | Where-Object { !$_.IsMemoryOptimized -and !$_.HasSparseColumn }) {
                            if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                                Write-Message -Level Warning -Message "Reached max run time of $MaxRunTime"
                                break
                            }
                            foreach ($p in $($obj.PhysicalPartitions | Where-Object { $_.DataCompression -notin ($CompressionType, 'ColumnStore', 'ColumnStoreArchive') })) {
                                Write-Message -Level Verbose -Message "Compressing table $($obj.Schema).$($obj.Name)"
                                try {
                                    $($obj.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $p.PartitionNumber }).DataCompression = $CompressionType
                                    $obj.OnlineHeapOperation = $CanDoOnlineOperation
                                    $obj.Rebuild()
                                } catch {
                                    Stop-Function -Message "Compression failed for $instance - $db - table $($obj.Schema).$($obj.Name) - partition $($p.PartitionNumber)" -Target $db -ErrorRecord $_ -Continue
                                }
                                [PSCustomObject]@{
                                    ComputerName                  = $server.ComputerName
                                    InstanceName                  = $server.ServiceName
                                    SqlInstance                   = $server.DomainInstanceName
                                    Database                      = $db.Name
                                    Schema                        = $obj.Schema
                                    TableName                     = $obj.Name
                                    IndexName                     = $null
                                    Partition                     = $p.PartitionNumber
                                    IndexID                       = 0
                                    IndexType                     = Switch ($obj.HasHeapIndex) { $false { "ClusteredIndex" } $true { "Heap" } }
                                    PercentScan                   = $null
                                    PercentUpdate                 = $null
                                    RowEstimatePercentOriginal    = $null
                                    PageEstimatePercentOriginal   = $null
                                    CompressionTypeRecommendation = $CompressionType.ToUpper()
                                    SizeCurrent                   = $null
                                    SizeRequested                 = $null
                                    PercentCompression            = $null
                                    AlreadyProcessed              = "True"
                                }
                            }

                            foreach ($index in $($obj.Indexes | Where-Object { !$_.IsMemoryOptimized -and $_.IndexType -notmatch 'Columnstore' })) {
                                if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                                    Write-Message -Level Warning -Message "Reached max run time of $MaxRunTime"
                                    break
                                }
                                foreach ($p in $($index.PhysicalPartitions | Where-Object { $_.DataCompression -ne $CompressionType })) {
                                    Write-Message -Level Verbose -Message "Compressing $($Index.IndexType) $($Index.Name) Partition $($p.PartitionNumber)"
                                    try {
                                        ## There is a bug in SMO where setting compression to None at the index level doesn't work
                                        ## Once this UserVoice item is fixed the workaround can be removed
                                        ## https://feedback.azure.com/forums/908035-sql-server/suggestions/34080112-data-compression-smo-bug
                                        if ($CompressionType -eq "None") {
                                            $query = "ALTER INDEX [$($index.Name)] ON $($index.Parent) REBUILD PARTITION = ALL WITH"
                                            if ($CanDoOnlineOperation) {
                                                $query += "(DATA_COMPRESSION = $CompressionType, ONLINE = ON)"
                                            } else {
                                                $query += "(DATA_COMPRESSION = $CompressionType)"
                                            }
                                            $Server.Query($query, $db.Name)
                                        } else {
                                            $($index.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                            $index.OnlineIndexOperation = $CanDoOnlineOperation
                                            $index.Rebuild()
                                        }
                                    } catch {
                                        Stop-Function -Message "Compression failed for $instance - $db - table $($obj.Schema).$($obj.Name) - index $($index.Name) - partition $($p.PartitionNumber)" -Target $db -ErrorRecord $_ -Continue
                                    }
                                    [PSCustomObject]@{
                                        ComputerName                  = $server.ComputerName
                                        InstanceName                  = $server.ServiceName
                                        SqlInstance                   = $server.DomainInstanceName
                                        Database                      = $db.Name
                                        Schema                        = $obj.Schema
                                        TableName                     = $obj.Name
                                        IndexName                     = $index.Name
                                        Partition                     = $p.PartitionNumber
                                        IndexID                       = $index.Id
                                        IndexType                     = $index.IndexType
                                        PercentScan                   = $null
                                        PercentUpdate                 = $null
                                        RowEstimatePercentOriginal    = $null
                                        PageEstimatePercentOriginal   = $null
                                        CompressionTypeRecommendation = $CompressionType.ToUpper()
                                        SizeCurrent                   = $null
                                        SizeRequested                 = $null
                                        PercentCompression            = $null
                                        AlreadyProcessed              = "True"
                                    }
                                }
                            }
                        }
                        foreach ($index in $($server.Databases[$($db.name)].Views | Where-Object { $_.Indexes }).Indexes) {
                            foreach ($p in $($index.PhysicalPartitions | Where-Object { $_.DataCompression -ne $CompressionType })) {
                                Write-Message -Level Verbose -Message "Compressing $($index.IndexType) $($index.Name) Partition $($p.PartitionNumber)"
                                try {
                                    ## There is a bug in SMO where setting compression to None at the index level doesn't work
                                    ## Once this UserVoice item is fixed the workaround can be removed
                                    ## https://feedback.azure.com/forums/908035-sql-server/suggestions/34080112-data-compression-smo-bug
                                    if ($CompressionType -eq "None") {
                                        if ($CanDoOnlineOperation) {
                                            $query += "(DATA_COMPRESSION = $CompressionType, ONLINE = ON)"
                                        } else {
                                            $query += "(DATA_COMPRESSION = $CompressionType)"
                                        }
                                        $Server.Query($query, $db.Name)
                                    } else {
                                        $($index.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                        $index.OnlineIndexOperation = $CanDoOnlineOperation
                                        $index.Rebuild()
                                    }
                                } catch {
                                    Stop-Function -Message "Compression failed for $instance - $db - table $($obj.Schema).$($obj.Name) - index $($index.Name) - partition $($p.PartitionNumber)" -Target $db -ErrorRecord $_ -Continue
                                }
                                [PSCustomObject]@{
                                    ComputerName                  = $server.ComputerName
                                    InstanceName                  = $server.ServiceName
                                    SqlInstance                   = $server.DomainInstanceName
                                    Database                      = $db.Name
                                    Schema                        = $obj.Schema
                                    TableName                     = $obj.Name
                                    IndexName                     = $index.Name
                                    Partition                     = $p.PartitionNumber
                                    IndexID                       = $index.Id
                                    IndexType                     = $index.IndexType
                                    PercentScan                   = $null
                                    PercentUpdate                 = $null
                                    RowEstimatePercentOriginal    = $null
                                    PageEstimatePercentOriginal   = $null
                                    CompressionTypeRecommendation = $CompressionType.ToUpper()
                                    SizeCurrent                   = $null
                                    SizeRequested                 = $null
                                    PercentCompression            = $null
                                    AlreadyProcessed              = "True"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}