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
        The database(s) to process - this list is auto populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto populated from the server.

    .PARAMETER Table
        The table(s) to process. If unspecified, all tables will be processed.

    .PARAMETER CompressionType
        Control the compression type applied. Default is 'Recommended' which uses the Tiger Team query to use the most appropriate setting per object. Other option is to compress all objects to either Row or Page.

    .PARAMETER MaxRunTime
        Will continue to alter tables and indexes for the given amount of minutes.

    .PARAMETER PercentCompression
        Will only work on the tables/indexes that have the calculated savings at and higher for the given number provided.

    .PARAMETER ForceOfflineRebuilds
        By default, this function prefers online rebuilds over offline ones.
        If you are on a supported version of SQL Server but still prefer to do offline rebuilds, enable this flag

    .PARAMETER InputObject
        Takes the output of Test-DbaDbCompression as an object and applied compression based on those recommendations.

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