function Set-DbaDbCompression {
    <#
        .SYNOPSIS
            Sets tables and indexes with preferred compression setting.

        .DESCRIPTION
            This function set the appropriate compression recommendation.
            Remember Uptime is critical, the longer uptime, the more accurate the analysis is.
            You would probably be best if you utilized Get-DbaUptime first, before running this command.

            Set-DbaDbCompression script derived from GitHub and the tigertoolbox
            (https://github.com/Microsoft/tigertoolbox/tree/master/Evaluate-Compression-Gains)

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            SqlCredential object to connect as. If not specified, current Windows login will be used.

        .PARAMETER Database
            The database(s) to process - this list is auto populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            The database(s) to exclude - this list is auto populated from the server.



        .PARAMETER MaxRunTime
            Will continue to alter tables and indexes for the given amount of minutes.

        .PARAMETER PercentCompression
            Will only work on the tables/indexes that have the calculated savings at and higher for the given number provided.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Jason Squires (@js_0505, jstexasdba@gmail.com)
            Tags: Compression, Table, Database
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Set-DbaDbCompression

        .EXAMPLE
            Set-DbaDbCompression -SqlInstance localhost -MaxRunTime 60 -PercentCompression 25

            Set the compression run time to 60 minutes and will start the compression of tables/indexes that have a difference of 25% or higher between current and recommended.

        .EXAMPLE
            Set-DbaDbCompression -SqlInstance ServerA -Database DBName -PercentCompression 25 | Out-GridView

            Will compress tables/indexes within the specified database with no time limit. Only objects that have a difference of 25% or higher between current and recommended will be compressed and the results into a nicely formated GridView.

        .EXAMPLE
            $cred = Get-Credential sqladmin
            Set-DbaDbCompression -SqlInstance ServerA -ExcludeDatabase Database -SqlCredential $cred -MaxRunTime 60 -PercentCompression 25

            Set the compression run time to 60 minutes and will start the compression of tables/indexes for all databases except the specified excluded database. Only objects that have a difference of 25% or higher between current and recommended will be compressed.

        .EXAMPLE
            $servers = 'Server1','Server2'
            foreach ($svr in $servers)
            {
                Set-DbaDbCompression -SqlInstance $svr -MaxRunTime 60 -PercentCompression 25 | Export-Csv -Path C:\temp\CompressionAnalysisPAC.csv -Append
            }

            Set the compression run time to 60 minutes and will start the compression of tables/indexes across all listed servers that have a difference of 25% or higher between current and recommended. Output of command is exported to a csv.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("Recommended", "PAGE", "ROW")]$CompressionType = "Recommended",
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [int]$MaxRunTime = 0,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [int]$PercentCompression,
        $InputObject,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        $starttime = Get-Date
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance" -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SourceSqlCredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            $Server.ConnectionContext.StatementTimeout = 0

            #The reason why we do this is because of SQL 2016 and they now allow for compression on standard edition.
            if ($Server.EngineEdition -notmatch 'Enterprise' -and $Server.VersionMajor -lt '13') {
                Stop-Function -Message "Only SQL Server Enterprise Edition supports compression on $Server" -Target $Server -Continue
            }
            try {
                $dbs = $server.Databases
                if ($Database) {
                    $dbs = $dbs | Where-Object { $Database -contains $_.Name -and $_.IsAccessible -and $_.IsSystemObject -EQ 0 }
                }
                else {
                    $dbs = $dbs | Where-Object { $_.IsAccessible -and $_.IsSystemObject -EQ 0 }
                }

                if (Test-Bound "ExcludeDatabase") {
                    $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
                }
            }
            catch {
                Stop-Function -Message "Unable to gather list of databases for $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            $results = @()
            foreach ($db in $dbs) {
                try {
                    Write-Message -Level Verbose -Message "Querying $instance - $db"
                    if ($db.status -ne 'Normal' -or $db.IsAccessible -eq $false) {
                        Write-Message -Level Warning -Message "$db is not accessible." -Target $db

                        continue
                    }
                    if ($db.CompatibilityLevel -lt 'Version100') {
                        Stop-Function -Message "$db has a compatibility level lower than Version100 and will be skipped." -Target $db -Continue
                    }
                    if ($CompressionType -eq "Recommended") {
                        if (Test-Bound "InputObject") {
                            Write-Message -Level Verbose -Message "Using passed in compression suggestions"
                            $compressionSuggestion = $InputObject | Where-Object {$_.Database -eq $db.name}
                            Write-Message -Level Verbose -Message "Object count for database: $($db.name) - $($compressionSuggestion.count)"
                        }
                        else {
                            Write-Message -Level Verbose -Message "Testing database for compression suggestions for $instance.$db"
                            $compressionSuggestion = Test-DbaDbCompression -SqlInstance $server -Database $db.Name
                        }
                    }
                }
                catch {
                    Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }

                try {
                    if ($CompressionType -eq "Recommended") {
                        Write-Message -Level Verbose -Message "Applying suggested compression settins using Test-DbaDbCompression"
                        $results += $compressionSuggestion | Select-Object *, @{l = 'AlreadyProcesssed'; e = {"False"}}
                        foreach ($obj in ($results | Where-Object {$_.CompressionTypeRecommendation -ne 'NO_GAIN' -and $_.PercentCompression -ge $PercentCompression} | Sort-Object PercentCompression -Descending)) {
                            #check time limit isn't met
                            if ($MaxRunTime -ne 0 -and ($(get-date) - $starttime).Minutes -ge $MaxRunTime) {
                                Write-Message -Level Verbose -Message "Reached max run time of $MaxRunTime"
                                break
                            }

                            if ($obj.indexId -le 1) {
                                ##heaps and clustered indexes
                                Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName)"
                                $($server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].PhysicalPartitions | Where-Object {$_.PartitionNumber -eq $obj.Partition}).DataCompression = $($obj.CompressionTypeRecommendation)
                                $server.Databases[$obj.Database].Tables[$obj.TableName, $($obj.Schema)].Rebuild()
                                $obj.AlreadyProcesssed = "True"
                            }
                            else {
                                ##nonclustered indexes
                                Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName).$($obj.IndexName)"
                                $($server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Indexes[$obj.IndexName].PhysicalPartitions | Where-Object {$_.PartitionNumber -eq $obj.Partition}).DataCompression = $($obj.CompressionTypeRecommendation)
                                $server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Indexes[$obj.IndexName].Rebuild()
                                $obj.AlreadyProcesssed = "True"
                            }
                        }
                    }
                    else {
                        Write-Message -Level Verbose -Message "Applying $CompressionType compression to all objects in $($db.name)"
                        ##Compress all objects to $compressionType
                        foreach ($obj in $server.Databases[$($db.name)].Tables) {
                            foreach ($index in $($obj.Indexes)) {  # | Where-Object {$_.Id -ne 0}
                                if($obj.HasHeapIndex) {
                                        if ($MaxRunTime -ne 0 -and ($(get-date) - $starttime).Minutes -ge $MaxRunTime) {
                                            Write-Message -Level Verbose -Message "Reached max run time of $MaxRunTime"
                                            break
                                        }
                                        foreach ($p in $obj.PhysicalPartitions) {
                                            Write-Message -Level Verbose -Message "Compressing heap $($obj.Schema).$($obj.Name)"
                                            $($obj.PhysicalPartitions | Where-Object {$_.PartitionNumber -eq $P.PartitionNumber}).DataCompression = $CompressionType

                                            $results +=
                                            [pscustomobject]@{
                                                ComputerName                  = $server.NetName
                                                InstanceName                  = $server.ServiceName
                                                SqlInstance                   = $server.DomainInstanceName
                                                Database                      = $db.Name
                                                Schema                        = $obj.Schema
                                                TableName                     = $obj.Name
                                                IndexName                     = $null
                                                Partition                     = $p.Partition
                                                IndexID                       = $null
                                                IndexType                     = $null
                                                PercentScan                   = $null
                                                PercentUpdate                 = $null
                                                RowEstimatePercentOriginal    = $null
                                                PageEstimatePercentOriginal   = $null
                                                CompressionTypeRecommendation = $CompressionType
                                                SizeCurrent                   = $null
                                                SizeRequested                 = $null
                                                PercentCompression            = $null
                                                AlreadyProcesssed             = "True"
                                        }
                                    }
                                    $obj.Rebuild()
                                }

                                if ($MaxRunTime -ne 0 -and ($(get-date) - $starttime).Minutes -ge $MaxRunTime) {
                                    Write-Message -Level Verbose -Message "Reached max run time of $MaxRunTime"
                                    break
                                }
                                Write-Message -Level Verbose -Message "Compressing $($Index.IndexType) $($Index.Name)"
                                foreach ($p in $index.PhysicalPartitions) {
                                    $($Index.PhysicalPartitions | Where-Object {$_.PartitionNumber -eq $P.PartitionNumber}).DataCompression = $CompressionType
                                    $results +=
                                    [pscustomobject]@{
                                        ComputerName                  = $server.NetName
                                        InstanceName                  = $server.ServiceName
                                        SqlInstance                   = $server.DomainInstanceName
                                        Database                      = $db.Name
                                        Schema                        = $obj.Schema
                                        TableName                     = $obj.Name
                                        IndexName                     = $index.IndexName
                                        Partition                     = $p.Partition
                                        IndexID                       = $index.IndexID
                                        IndexType                     = $index.IndexType
                                        PercentScan                   = $null
                                        PercentUpdate                 = $null
                                        RowEstimatePercentOriginal    = $null
                                        PageEstimatePercentOriginal   = $null
                                        CompressionTypeRecommendation = $CompressionType
                                        SizeCurrent                   = $null
                                        SizeRequested                 = $null
                                        PercentCompression            = $null
                                        AlreadyProcesssed             = "True"
                                    }
                                }
                                $index.Rebuild()

                            }







                        }


                    }
                }
                catch {
                    Stop-Function -Message "Compression failed for $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }
            }
            return $results
           # Select-DefaultView -InputOpject $results -Property Parent,
        }
    }
}