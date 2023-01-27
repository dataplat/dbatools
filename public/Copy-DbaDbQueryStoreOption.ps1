function Copy-DbaDbQueryStoreOption {
    <#
    .SYNOPSIS
        Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.

    .DESCRIPTION
        Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2016 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SourceDatabase
        Specifies the database to copy the Query Store configuration from.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2016 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationDatabase
        Specifies a list of databases that will receive a copy of the Query Store configuration of the SourceDatabase.

    .PARAMETER Exclude
        Specifies a list of databases which will NOT receive a copy of the Query Store configuration.

    .PARAMETER AllDatabases
        If this switch is enabled, the Query Store configuration will be copied to all databases on the destination instance.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: QueryStore
        Author: Enrico van de Laar (@evdlaar) | Tracy Boggiano (@Tracy Boggiano)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaDbQueryStoreOption

    .EXAMPLE
        PS C:\> Copy-DbaDbQueryStoreOption -Source ServerA\SQL -SourceDatabase AdventureWorks -Destination ServerB\SQL -AllDatabases

        Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL instance and apply it on all user databases in the ServerB\SQL Instance.

    .EXAMPLE
        PS C:\> Copy-DbaDbQueryStoreOption -Source ServerA\SQL -SourceDatabase AdventureWorks -Destination ServerB\SQL -DestinationDatabase WorldWideTraders

        Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL instance and apply it to the WorldWideTraders database in the ServerB\SQL Instance.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory, ValueFromPipeline)]
        [object]$SourceDatabase,
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$DestinationDatabase,
        [object[]]$Exclude,
        [switch]$AllDatabases,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # Grab the Query Store configuration from the SourceDatabase through the Get-DbaQueryStoreConfig function
        $SourceQSConfig = Get-DbaDbQueryStoreOption -SqlInstance $sourceServer -Database $SourceDatabase

        $sourceDB = Get-DbaDatabase -SqlInstance $sourceServer -Database $SourceDatabase

        if ($sourceServer.VersionMajor -eq 14) {
            $QueryStoreOptions = $sourceDB.Query("SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode FROM sys.database_query_store_options;", $sourceDB.Name)
        } elseif ($sourceServer.VersionMajor -ge 15) {
            $QueryStoreOptions = $sourceDB.Query("SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode, capture_policy_execution_count AS CustomCapturePolicyExecutionCount, capture_policy_stale_threshold_hours AS CustomCapturePolicyStaleThresholdHours, capture_policy_total_compile_cpu_time_ms AS CustomCapturePolicyTotalCompileCPUTimeMS, capture_policy_total_execution_cpu_time_ms AS CustomCapturePolicyTotalExecutionCPUTimeMS FROM sys.database_query_store_options;", $sourceDB.Name)
        }

        foreach ($destinstance in $Destination) {

            if (!$DestinationDatabase -and !$Exclude -and !$AllDatabases) {
                Stop-Function -Message "You must specify databases to execute against using either -DestinationDatabase, -Exclude or -AllDatabases." -Continue
            }

            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            # We have to exclude all the system databases since they cannot have the Query Store feature enabled
            $destDBs = Get-DbaDatabase -SqlInstance $destServer -ExcludeSystem

            if ($DestinationDatabase.count -gt 0) {
                $destDBs = $destDBs | Where-Object { $DestinationDatabase -contains $_.Name }
            }

            if ($Exclude.count -gt 0) {
                $destDBs = $destDBs | Where-Object { $exclude -notcontains $_.Name }
            }

            if ($destDBs.count -eq 0) {
                Stop-Function -Message "No matching databases found. Check the spelling and try again." -Continue
            }

            foreach ($destDB in $destDBs) {
                # skipping the database if the source and destination are the same instance
                if (($sourceServer.Name -eq $destServer) -and ($SourceDatabase -eq $destDB.Name)) {
                    continue
                }
                Write-Message -Message "Processing destination database: $destDB on $destServer." -Level Verbose
                $copyQueryStoreStatus = [pscustomobject]@{
                    SourceServer          = $sourceServer.name
                    SourceDatabase        = $SourceDatabase
                    SourceDatabaseID      = $sourceDB.ID
                    DestinationServer     = $destServer
                    Name                  = $destDB.name
                    DestinationDatabaseID = $destDB.ID
                    Type                  = "QueryStore Configuration"
                    Status                = $null
                    DateTime              = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($destDB.IsAccessible -eq $false) {
                    $copyQueryStoreStatus.Status = "Skipped"
                    Stop-Function -Message "The database $destDB on server $destServer is not accessible. Skipping database." -Continue
                }

                Write-Message -Message "Executing Set-DbaQueryStoreConfig." -Level Verbose
                # Set the Query Store configuration through the Set-DbaQueryStoreConfig function
                if ($PSCmdlet.ShouldProcess("$destDB", "Copying QueryStoreConfig")) {
                    try {
                        if ($sourceServer.VersionMajor -eq 13) {
                            $setDbaDbQueryStoreOptionParameters = @{
                                SqlInstance         = $destServer
                                SqlCredential       = $DestinationSqlCredential
                                Database            = $destDB.name
                                State               = $SourceQSConfig.ActualState
                                FlushInterval       = $SourceQSConfig.DataFlushIntervalInSeconds
                                CollectionInterval  = $SourceQSConfig.StatisticsCollectionIntervalInMinutes
                                MaxSize             = $SourceQSConfig.MaxStorageSizeInMB
                                CaptureMode         = $SourceQSConfig.QueryCaptureMode
                                CleanupMode         = $SourceQSConfig.SizeBasedCleanupMode
                                StaleQueryThreshold = $SourceQSConfig.StaleQueryThresholdInDays
                            }
                        } elseif ($sourceServer.VersionMajor -eq 14) {
                            $setDbaDbQueryStoreOptionParameters = @{
                                SqlInstance          = $destServer
                                SqlCredential        = $DestinationSqlCredential
                                Database             = $destDB.name
                                State                = $SourceQSConfig.ActualState
                                FlushInterval        = $SourceQSConfig.DataFlushIntervalInSeconds
                                CollectionInterval   = $SourceQSConfig.StatisticsCollectionIntervalInMinutes
                                MaxSize              = $SourceQSConfig.MaxStorageSizeInMB
                                CaptureMode          = $SourceQSConfig.QueryCaptureMode
                                CleanupMode          = $SourceQSConfig.SizeBasedCleanupMode
                                StaleQueryThreshold  = $SourceQSConfig.StaleQueryThresholdInDays
                                MaxPlansPerQuery     = $QueryStoreOptions.MaxPlansPerQuery
                                WaitStatsCaptureMode = $QueryStoreOptions.WaitStatsCaptureMode
                            }
                        } elseif ($sourceServer.VersionMajor -ge 15) {
                            $setDbaDbQueryStoreOptionParameters = @{
                                SqlInstance                                = $destServer
                                SqlCredential                              = $DestinationSqlCredential
                                Database                                   = $destDB.name
                                State                                      = $SourceQSConfig.ActualState
                                FlushInterval                              = $SourceQSConfig.DataFlushIntervalInSeconds
                                CollectionInterval                         = $SourceQSConfig.StatisticsCollectionIntervalInMinutes
                                MaxSize                                    = $SourceQSConfig.MaxStorageSizeInMB
                                CaptureMode                                = $SourceQSConfig.QueryCaptureMode
                                CleanupMode                                = $SourceQSConfig.SizeBasedCleanupMode
                                StaleQueryThreshold                        = $SourceQSConfig.StaleQueryThresholdInDays
                                MaxPlansPerQuery                           = $QueryStoreOptions.MaxPlansPerQuery
                                WaitStatsCaptureMode                       = $QueryStoreOptions.WaitStatsCaptureMode
                                CustomCapturePolicyExecutionCount          = $QueryStoreOptions.CustomCapturePolicyExecutionCount
                                CustomCapturePolicyTotalCompileCPUTimeMS   = $QueryStoreOptions.CustomCapturePolicyTotalCompileCPUTimeMS
                                CustomCapturePolicyTotalExecutionCPUTimeMS = $QueryStoreOptions.CustomCapturePolicyTotalExecutionCPUTimeMS
                                CustomCapturePolicyStaleThresholdHours     = $QueryStoreOptions.CustomCapturePolicyStaleThresholdHours
                            }
                        }

                        $null = Set-DbaDbQueryStoreOption @setDbaDbQueryStoreOptionParameters
                        $copyQueryStoreStatus.Status = "Successful"
                    } catch {
                        $copyQueryStoreStatus.Status = "Failed"
                        Stop-Function -Message "Issue setting Query Store on $destDB." -Target $destDB -ErrorRecord $_ -Continue
                    }
                    $copyQueryStoreStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }
    }
}