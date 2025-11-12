function Set-DbaDbQueryStoreOption {
    <#
    .SYNOPSIS
        Configures Query Store settings to control query performance data collection and retention.

    .DESCRIPTION
        Modifies Query Store configuration options for one or more databases, allowing you to control how SQL Server captures, stores, and manages query execution statistics. Query Store acts as a performance data recorder, tracking query plans and runtime statistics over time for performance analysis and plan regression troubleshooting.

        This function lets you set the operational state (enabled/disabled), adjust data collection intervals, configure storage limits, control which queries get captured, and manage data retention policies. You can also enable wait statistics capture and configure advanced custom capture policies in SQL Server 2019 and later.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        Specifies which databases to configure Query Store options for. Accepts database names, wildcards, or database objects from Get-DbaDatabase.
        Use this when you need to configure Query Store for specific databases instead of all user databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from Query Store configuration changes. System databases (master, tempdb, model) are automatically excluded.
        Useful when you want to configure most databases but skip certain ones like staging or temporary databases.

    .PARAMETER AllDatabases
        Configures Query Store options for all user databases on the instance. System databases are automatically excluded.
        Use this switch when you want to apply consistent Query Store settings across all user databases without specifying individual database names.

    .PARAMETER State
        Controls Query Store operational state: ReadWrite enables full data collection, ReadOnly preserves existing data but stops new collection, Off disables Query Store completely.
        Set to ReadWrite to start collecting query performance data, or ReadOnly when troubleshooting performance issues without adding new data overhead.

    .PARAMETER FlushInterval
        Sets how frequently Query Store flushes runtime statistics from memory to disk, in seconds. Default is 900 seconds (15 minutes).
        Lower values provide more real-time data persistence but increase disk I/O; higher values reduce I/O but risk losing recent data during unexpected shutdowns.

    .PARAMETER CollectionInterval
        Defines how often Query Store aggregates runtime statistics into discrete time intervals, in minutes. Default is 60 minutes.
        Shorter intervals provide finer granularity for performance analysis but consume more storage; longer intervals reduce storage overhead but provide less detailed trending data.

    .PARAMETER MaxSize
        Sets the maximum storage space Query Store can consume in the database, in megabytes. Default is 100 MB.
        Configure based on your database size and query volume; busy OLTP databases may need several GB, while smaller databases can use the default.

    .PARAMETER CaptureMode
        Determines which queries Query Store captures: Auto captures relevant queries based on execution count and resource consumption, All captures every query, None captures no new queries, Custom uses defined capture policies (SQL 2019+).
        Use Auto for most production environments to avoid capturing trivial queries; use All for comprehensive troubleshooting or development environments.

    .PARAMETER CleanupMode
        Controls automatic cleanup of old Query Store data when approaching the MaxSize limit: Auto removes oldest data first, Off disables automatic cleanup.
        Set to Auto to prevent Query Store from reaching capacity and stopping data collection; use Off only when you want manual control over data retention.

    .PARAMETER StaleQueryThreshold
        Specifies how many days Query Store retains data for queries that haven't executed recently, used by automatic cleanup processes.
        Set to 30-90 days for most environments; longer retention helps with historical analysis but consumes more space, shorter retention frees space faster.

    .PARAMETER MaxPlansPerQuery
        Limits how many execution plans Query Store retains for each individual query. Default is 200 plans per query (SQL Server 2017+).
        Higher values help track plan variations in dynamic environments but consume more space; lower values reduce storage but may miss important plan changes.

    .PARAMETER WaitStatsCaptureMode
        Enables or disables wait statistics collection in Query Store (SQL Server 2017+). Options are On or Off.
        Enable wait stats capture when you need detailed performance analysis including what queries are waiting for; disable to reduce overhead in high-throughput systems.

    .PARAMETER CustomCapturePolicyExecutionCount
        Sets minimum execution count threshold for capturing queries when CaptureMode is Custom (SQL Server 2019+). Queries must execute at least this many times to be captured.
        Use values like 5-10 to capture queries that run regularly but avoid one-time or rarely executed queries that don't impact performance.

    .PARAMETER CustomCapturePolicyTotalCompileCPUTimeMS
        Sets minimum compilation CPU time threshold in milliseconds for capturing queries when CaptureMode is Custom (SQL Server 2019+).
        Set to values like 1000ms (1 second) to capture queries with significant compilation overhead, helping identify queries that need plan guides or parameter optimization.

    .PARAMETER CustomCapturePolicyTotalExecutionCPUTimeMS
        Sets minimum total execution CPU time threshold in milliseconds for capturing queries when CaptureMode is Custom (SQL Server 2019+).
        Use values like 100ms to focus on queries consuming significant CPU resources, filtering out lightweight queries that don't impact overall performance.

    .PARAMETER CustomCapturePolicyStaleThresholdHours
        Defines how many hours a query can remain inactive before Query Store stops tracking new statistics for it when CaptureMode is Custom (SQL Server 2019+).
        Set to 24-168 hours (1-7 days) to balance between capturing actively used queries and avoiding resource consumption on dormant queries.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Changing Desired State" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: QueryStore
        Author: Enrico van de Laar (@evdlaar) | Tracy Boggiano (@TracyBoggiano)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbQueryStoreOption

    .EXAMPLE
        PS C:\> Set-DbaDbQueryStoreOption -SqlInstance ServerA\SQL -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode All -CleanupMode Auto -StaleQueryThreshold 100 -AllDatabases

        Configure the Query Store settings for all user databases in the ServerA\SQL Instance.

    .EXAMPLE
        PS C:\> Set-DbaDbQueryStoreOption -SqlInstance ServerA\SQL -FlushInterval 600

        Only configure the FlushInterval setting for all Query Store databases in the ServerA\SQL Instance.

    .EXAMPLE
        PS C:\> Set-DbaDbQueryStoreOption -SqlInstance ServerA\SQL -Database AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

        Configure the Query Store settings for the AdventureWorks database in the ServerA\SQL Instance.

    .EXAMPLE
        PS C:\> Set-DbaDbQueryStoreOption -SqlInstance ServerA\SQL -Exclude AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

        Configure the Query Store settings for all user databases except the AdventureWorks database in the ServerA\SQL Instance.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [ValidateSet('ReadWrite', 'ReadOnly', 'Off')]
        [string[]]$State,
        [int64]$FlushInterval,
        [int64]$CollectionInterval,
        [int64]$MaxSize,
        [ValidateSet('Auto', 'All', 'None', 'Custom')]
        [string[]]$CaptureMode,
        [ValidateSet('Auto', 'Off')]
        [string[]]$CleanupMode,
        [int64]$StaleQueryThreshold,
        [int64]$MaxPlansPerQuery,
        [ValidateSet('On', 'Off')]
        [string[]]$WaitStatsCaptureMode,
        [int64]$CustomCapturePolicyExecutionCount,
        [int64]$CustomCapturePolicyTotalCompileCPUTimeMS,
        [int64]$CustomCapturePolicyTotalExecutionCPUTimeMS,
        [int64]$CustomCapturePolicyStaleThresholdHours,
        [switch]$EnableException
    )
    begin {
        $ExcludeDatabase += 'master', 'tempdb', "model"
    }

    process {
        if (-not $Database -and -not $ExcludeDatabase -and -not $AllDatabases) {
            Stop-Function -Message "You must specify a database(s) to execute against using either -Database, -ExcludeDatabase or -AllDatabases"
            return
        }

        if (-not $State -and -not $FlushInterval -and -not $CollectionInterval -and -not $MaxSize -and -not $CaptureMode -and -not $CleanupMode -and -not $StaleQueryThreshold -and -not $MaxPlansPerQuery -and -not $WaitStatsCaptureMode -and -not $CustomCapturePolicyExecutionCount -and -not $CustomCapturePolicyTotalCompileCPUTimeMS -and -not $CustomCapturePolicyTotalExecutionCPUTimeMS -and -not $CustomCapturePolicyStaleThresholdHours) {
            Stop-Function -Message "You must specify something to change."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 13
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($CaptureMode -contains "Custom" -and $server.VersionMajor -lt 15) {
                Stop-Function -Message "Custom capture mode can onlly be set in SQL Server 2019 and above" -Continue
            }

            if (($CustomCapturePolicyExecutionCount -or $CustomCapturePolicyTotalCompileCPUTimeMS -or $CustomCapturePolicyTotalExecutionCPUTimeMS -or $CustomCapturePolicyStaleThresholdHours) -and $server.VersionMajor -lt 15) {
                Write-Message -Level Warning -Message "Custom Capture Policies can only be set in SQL Server 2019 and above. These options will be skipped for $instance"
            }

            # We have to exclude all the system databases since they cannot have the Query Store feature enabled
            $dbs = Get-DbaDatabase -SqlInstance $server -ExcludeDatabase $ExcludeDatabase -Database $Database | Where-Object { $_.IsAccessible -and !$_.IsDatabaseSnapshot }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.name) on $instance"

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db on server $instance is not accessible. Skipping database."
                    continue
                }

                if ($State) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing DesiredState to $state")) {
                        $db.QueryStoreOptions.DesiredState = $State
                        $db.QueryStoreOptions.Alter()
                        $db.QueryStoreOptions.Refresh()
                    }
                }

                if ($db.QueryStoreOptions.DesiredState -eq "Off" -and (Test-Bound -Parameter State -Not)) {
                    Write-Message -Level Warning -Message "State is set to Off; cannot change values. Please update State to ReadOnly or ReadWrite."
                    continue
                }

                if ($FlushInterval) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing DataFlushIntervalInSeconds to $FlushInterval")) {
                        $db.QueryStoreOptions.DataFlushIntervalInSeconds = $FlushInterval
                    }
                }

                if ($CollectionInterval) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing StatisticsCollectionIntervalInMinutes to $CollectionInterval")) {
                        $db.QueryStoreOptions.StatisticsCollectionIntervalInMinutes = $CollectionInterval
                    }
                }

                if ($MaxSize) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing MaxStorageSizeInMB to $MaxSize")) {
                        $db.QueryStoreOptions.MaxStorageSizeInMB = $MaxSize
                    }
                }

                if ($CaptureMode) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing QueryCaptureMode to $CaptureMode")) {
                        $db.QueryStoreOptions.QueryCaptureMode = $CaptureMode
                    }
                }

                if ($CleanupMode) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing SizeBasedCleanupMode to $CleanupMode")) {
                        $db.QueryStoreOptions.SizeBasedCleanupMode = $CleanupMode
                    }
                }

                if ($StaleQueryThreshold) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing StaleQueryThresholdInDays to $StaleQueryThreshold")) {
                        $db.QueryStoreOptions.StaleQueryThresholdInDays = $StaleQueryThreshold
                    }
                }

                $query = ""

                if ($server.VersionMajor -ge 14) {
                    if ($MaxPlansPerQuery) {
                        if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing MaxPlansPerQuery to $($MaxPlansPerQuery)")) {
                            $query += "ALTER DATABASE [$db] SET QUERY_STORE = ON (MAX_PLANS_PER_QUERY = $($MaxPlansPerQuery)); "
                        }
                    }

                    if ($WaitStatsCaptureMode) {
                        if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing WaitStatsCaptureMode to $($WaitStatsCaptureMode)")) {
                            if ($WaitStatsCaptureMode -eq "ON" -or $WaitStatsCaptureMode -eq "OFF") {
                                $query += "ALTER DATABASE [$db] SET QUERY_STORE = ON (WAIT_STATS_CAPTURE_MODE = $($WaitStatsCaptureMode)); "
                            }
                        }
                    }
                }

                if ($server.VersionMajor -ge 15) {
                    if ($db.QueryStoreOptions.QueryCaptureMode -eq "CUSTOM") {
                        if ($CustomCapturePolicyStaleThresholdHours) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyStaleThresholdHours to $($CustomCapturePolicyStaleThresholdHours)")) {
                                $query += "ALTER DATABASE [$db] SET QUERY_STORE = ON ( QUERY_CAPTURE_POLICY = ( STALE_CAPTURE_POLICY_THRESHOLD = $($CustomCapturePolicyStaleThresholdHours) HOURS)); "
                            }
                        }

                        if ($CustomCapturePolicyExecutionCount) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyExecutionCount to $($CustomCapturePolicyExecutionCount)")) {
                                $query += "ALTER DATABASE [$db] SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (EXECUTION_COUNT = $($CustomCapturePolicyExecutionCount))); "
                            }
                        }
                        if ($CustomCapturePolicyTotalCompileCPUTimeMS) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyTotalCompileCPUTimeMS to $($CustomCapturePolicyTotalCompileCPUTimeMS)")) {
                                $query += "ALTER DATABASE [$db] SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (TOTAL_COMPILE_CPU_TIME_MS = $($CustomCapturePolicyTotalCompileCPUTimeMS))); "
                            }
                        }

                        if ($CustomCapturePolicyTotalExecutionCPUTimeMS) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyTotalExecutionCPUTimeMS to $($CustomCapturePolicyTotalExecutionCPUTimeMS)")) {
                                $query += "ALTER DATABASE [$db] SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (TOTAL_EXECUTION_CPU_TIME_MS = $($CustomCapturePolicyTotalExecutionCPUTimeMS))); "
                            }
                        }
                    }
                }

                # Alter the Query Store Configuration
                if ($Pscmdlet.ShouldProcess("$db on $instance", "Altering Query Store configuration on database")) {
                    try {
                        $db.QueryStoreOptions.Alter()
                        $db.Alter()
                        $db.Refresh()

                        if ($query -ne "") {
                            $db.Query($query, $db.Name)
                        }
                    } catch {
                        Stop-Function -Message "Could not modify configuration." -Category InvalidOperation -InnerErrorRecord $_ -Target $db -Continue
                    }
                }

                if ($Pscmdlet.ShouldProcess("$db on $instance", "Getting results from Get-DbaDbQueryStoreOption")) {
                    Get-DbaDbQueryStoreOption -SqlInstance $server -Database $db.name -Verbose:$false
                }
            }
        }
    }
}