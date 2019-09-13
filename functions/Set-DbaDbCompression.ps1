function Set-DbaDbCompression {
    <#
    .SYNOPSIS
        Sets tables and indexes with preferred compression setting.

    .DESCRIPTION
        This function sets the appropriate compression recommendation, determined either by using the Tiger Team's query or set to the CompressionType parameter.

        Remember Uptime is critical for the Tiger Team query, the longer uptime, the more accurate the analysis is.
        You would probably be best if you utilized Get-DbaUptime first, before running this command.

        Set-DbaDbCompression script derived from GitHub and the tigertoolbox
        (https://github.com/Microsoft/tigertoolbox/tree/master/Evaluate-Compression-Gains)

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

    .PARAMETER CompressionType
        Control the compression type applied. Default is 'Recommended' which uses the Tiger Team query to use the most appropriate setting per object. Other option is to compress all objects to either Row or Page.

    .PARAMETER MaxRunTime
        Will continue to alter tables and indexes for the given amount of minutes.

    .PARAMETER PercentCompression
        Will only work on the tables/indexes that have the calculated savings at and higher for the given number provided.

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
        PS C:\> Set-DbaDbCompression -SqlInstance ServerA -Database DBName -CompressionType Page

        Utilizes Page compression for all objects in DBName on ServerA with no time limit.

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
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet("Recommended", "Page", "Row", "None")]$CompressionType = "Recommended",
        [int]$MaxRunTime = 0,
        [int]$PercentCompression = 0,
        $InputObject,
        [switch]$EnableException
    )

    process {
        $starttime = Get-Date
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failed to process Instance $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            $Server.ConnectionContext.StatementTimeout = 0

            #The reason why we do this is because of SQL 2016 and they now allow for compression on standard edition.
            if ($server.EngineEdition -notmatch 'Enterprise' -and $server.VersionMajor -lt '13') {
                Stop-Function -Message "Only SQL Server Enterprise Edition supports compression on $server" -Target $server -Continue
            }
            try {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -and $_.IsSystemObject -eq 0 }
                if ($Database) {
                    $dbs = $dbs | Where-Object { $_.Name -in $Database }
                }
                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $_.Name -NotIn $ExcludeDatabase }
                }
            } catch {
                Stop-Function -Message "Unable to gather list of databases for $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            foreach ($db in $dbs) {
                try {
                    Write-Message -Level Verbose -Message "Querying $instance - $db"
                    if ($db.status -ne 'Normal' -or $db.IsAccessible -eq $false) {
                        Write-Message -Level Warning -Message "$db is not accessible" -Target $db
                        continue
                    }
                    if ($db.CompatibilityLevel -lt 'Version100') {
                        Stop-Function -Message "$db has a compatibility level lower than Version100 and will be skipped." -Target $db -Continue
                    }
                    if ($CompressionType -eq "Recommended") {
                        if (Test-Bound "InputObject") {
                            Write-Message -Level Verbose -Message "Using passed in compression suggestions"
                            $compressionSuggestion = $InputObject | Where-Object { $_.Database -eq $db.name }
                        } else {
                            Write-Message -Level Verbose -Message "Testing database for compression suggestions for $instance.$db"
                            $compressionSuggestion = Test-DbaDbCompression -SqlInstance $server -Database $db.Name
                        }
                    }
                } catch {
                    Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }

                try {
                    if ($CompressionType -eq "Recommended") {
                        if ($Pscmdlet.ShouldProcess($db, "Applying suggested compression using results from Test-DbaDbCompression")) {
                            Write-Message -Level Verbose -Message "Applying suggested compression settings using Test-DbaDbCompression"
                            $results += $compressionSuggestion | Select-Object *, @{l = 'AlreadyProcessed'; e = { "False" } }
                            foreach ($obj in ($results | Where-Object { $_.CompressionTypeRecommendation -notin @('NO_GAIN', '?') -and $_.PercentCompression -ge $PercentCompression } | Sort-Object PercentCompression -Descending)) {
                                if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                                    Write-Message -Level Verbose -Message "Reached max run time of $MaxRunTime"
                                    break
                                }
                                if ($obj.indexId -le 1) {
                                    ##heaps and clustered indexes
                                    Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName)"
                                    $($server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $obj.Partition }).DataCompression = $($obj.CompressionTypeRecommendation)
                                    $server.Databases[$obj.Database].Tables[$obj.TableName, $($obj.Schema)].Rebuild()
                                    $obj.AlreadyProcessed = "True"
                                } else {
                                    ##nonclustered indexes
                                    Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName).$($obj.IndexName)"
                                    $($server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Indexes[$obj.IndexName].PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $obj.Partition }).DataCompression = $($obj.CompressionTypeRecommendation)
                                    $server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Indexes[$obj.IndexName].Rebuild()
                                    $obj.AlreadyProcessed = "True"
                                }
                                $obj
                            }
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($db, "Applying $CompressionType compression")) {
                            Write-Message -Level Verbose -Message "Applying $CompressionType compression to all objects in $($db.name)"
                            foreach ($obj in $server.Databases[$($db.name)].Tables | Where-Object { !$_.IsMemoryOptimized -and !$_.HasSparseColumn }) {
                                if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                                    Write-Message -Level Verbose -Message "Reached max run time of $MaxRunTime"
                                    break
                                }
                                foreach ($p in $($obj.PhysicalPartitions | Where-Object { $_.DataCompression -notin ($CompressionType, 'ColumnStore', 'ColumnStoreArchive') })) {
                                    Write-Message -Level Verbose -Message "Compressing table $($obj.Schema).$($obj.Name)"
                                    $($obj.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                    $obj.Rebuild()
                                    [pscustomobject]@{
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
                                        Write-Message -Level Verbose -Message "Reached max run time of $MaxRunTime"
                                        break
                                    }
                                    foreach ($p in $($index.PhysicalPartitions | Where-Object { $_.DataCompression -ne $CompressionType })) {
                                        Write-Message -Level Verbose -Message "Compressing $($Index.IndexType) $($Index.Name) Partition $($p.PartitionNumber)"

                                        ## There is a bug in SMO where setting compression to None at the index level doesn't work
                                        ## Once this UserVoice item is fixed the workaround can be removed
                                        ## https://feedback.azure.com/forums/908035-sql-server/suggestions/34080112-data-compression-smo-bug
                                        if ($CompressionType -eq "None") {
                                            $query = "ALTER INDEX [$($index.Name)] ON $($index.Parent) REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = $CompressionType)"
                                            $Server.Query($query, $db.Name)
                                        } else {
                                            $($Index.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                            $index.Rebuild()
                                        }

                                        [pscustomobject]@{
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

                                    ## There is a bug in SMO where setting compression to None at the index level doesn't work
                                    ## Once this UserVoice item is fixed the workaround can be removed
                                    ## https://feedback.azure.com/forums/908035-sql-server/suggestions/34080112-data-compression-smo-bug
                                    if ($CompressionType -eq "None") {
                                        $query = "ALTER INDEX [$($index.Name)] ON $($index.Parent) REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = $CompressionType)"
                                        $query
                                        $Server.Query($query, $db.Name)
                                    } else {
                                        $($index.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                        $index.Rebuild()
                                    }

                                    [pscustomobject]@{
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
                } catch {
                    Stop-Function -Message "Compression failed for $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}