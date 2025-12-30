function Get-DbaDbQueryStoreOption {
    <#
    .SYNOPSIS
        Retrieves Query Store configuration settings from databases across SQL Server instances.

    .DESCRIPTION
        Returns the complete Query Store configuration for user databases, including capture modes, storage limits, cleanup policies, and retention settings. This function helps DBAs audit Query Store configurations across their environment, identify databases with suboptimal settings, and ensure consistent Query Store policies. Query Store settings directly impact query performance monitoring, plan regression detection, and storage consumption, so regular configuration reviews are essential for maintaining optimal performance insights.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.QueryStoreOptions

        Returns one object per database with Query Store configuration settings. The base object is the QueryStoreOptions SMO object enhanced with additional properties and adjusted based on the SQL Server version.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: Name of the database
        - ActualState: Current Query Store state (ReadWrite, ReadOnly, or Off)
        - DataFlushIntervalInSeconds: Interval in seconds for flushing data to storage
        - StatisticsCollectionIntervalInMinutes: Interval in minutes for statistics collection
        - MaxStorageSizeInMB: Maximum storage size allocated for Query Store (in megabytes)
        - CurrentStorageSizeInMB: Current storage size being used by Query Store (in megabytes)
        - QueryCaptureMode: Query capture mode (All, Auto, None, or Custom)
        - SizeBasedCleanupMode: Cleanup mode when max storage is exceeded (Off, Auto)
        - StaleQueryThresholdInDays: Number of days after which a query is considered stale for cleanup

        Additional properties for SQL Server 2017 (v14) and later:
        - MaxPlansPerQuery: Maximum number of plans tracked per query
        - WaitStatsCaptureMode: Wait statistics capture mode (Off, On)

        Additional properties for SQL Server 2019 (v15) and later:
        - CustomCapturePolicyExecutionCount: Custom capture policy execution count threshold
        - CustomCapturePolicyTotalCompileCPUTimeMS: Custom capture policy compile CPU time threshold in milliseconds
        - CustomCapturePolicyTotalExecutionCPUTimeMS: Custom capture policy execution CPU time threshold in milliseconds
        - CustomCapturePolicyStaleThresholdHours: Custom capture policy stale threshold in hours

        All properties from the base SMO QueryStoreOptions object are accessible via Select-Object *, even though only default properties are displayed in standard output. The number of properties returned varies based on the SQL Server version of the target instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which user databases to retrieve Query Store configuration from. Accepts database names, wildcards, or arrays for multiple databases.
        Use this when you need to audit Query Store settings for specific databases rather than scanning your entire instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from Query Store configuration retrieval. System databases (master, tempdb, model) are automatically excluded.
        Useful for skipping databases that you know don't need Query Store monitoring or have restricted access permissions.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: QueryStore
        Author: Enrico van de Laar (@evdlaar) | Klaas Vandenberghe (@PowerDBAKlaas) | Tracy Boggiano (@TracyBoggiano)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbQueryStoreOption

    .EXAMPLE
        PS C:\> Get-DbaDbQueryStoreOption -SqlInstance ServerA\sql

        Returns Query Store configuration settings for every database on the ServerA\sql instance.

    .EXAMPLE
        PS C:\> Get-DbaDbQueryStoreOption -SqlInstance ServerA\sql | Where-Object {$_.ActualState -eq "ReadWrite"}

        Returns the Query Store configuration for all databases on ServerA\sql where the Query Store feature is in Read/Write mode.

    .EXAMPLE
        PS C:\> Get-DbaDbQueryStoreOption -SqlInstance localhost | format-table -AutoSize -Wrap

        Returns Query Store configuration settings for every database on the ServerA\sql instance inside a table format.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )
    begin {
        # We exclude model because SMO cannot tell if Query Store is enabled there
        $ExcludeDatabase += 'master', 'tempdb', "model"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 13
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # We have to exclude system databases since they cannot have the Query Store feature enabled
            $dbs = Get-DbaDatabase -SqlInstance $server -ExcludeDatabase $ExcludeDatabase -Database $Database | Where-Object IsAccessible

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.Name) on $instance"
                $qso = $db.QueryStoreOptions

                if ($server.VersionMajor -eq 14) {
                    $QueryStoreOptions = Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode FROM sys.database_query_store_options;" -As PSObject
                } elseif ($server.VersionMajor -ge 15) {
                    $QueryStoreOptions = Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode, capture_policy_execution_count AS CustomCapturePolicyExecutionCount, capture_policy_stale_threshold_hours AS CustomCapturePolicyStaleThresholdHours, capture_policy_total_compile_cpu_time_ms AS CustomCapturePolicyTotalCompileCPUTimeMS, capture_policy_total_execution_cpu_time_ms AS CustomCapturePolicyTotalExecutionCPUTimeMS FROM sys.database_query_store_options;" -As PSObject
                }

                Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $qso -MemberType NoteProperty Database -Value $db.Name

                if ($server.VersionMajor -eq 13) {
                    Select-DefaultView -InputObject $qso -Property ComputerName, InstanceName, SqlInstance, Database, ActualState, DataFlushIntervalInSeconds, StatisticsCollectionIntervalInMinutes, MaxStorageSizeInMB, CurrentStorageSizeInMB, QueryCaptureMode, SizeBasedCleanupMode, StaleQueryThresholdInDays
                } elseif ($server.VersionMajor -eq 14) {
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name MaxPlansPerQuery -Value $QueryStoreOptions.MaxPlansPerQuery
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name WaitStatsCaptureMode -Value $QueryStoreOptions.WaitStatsCaptureMode
                    Select-DefaultView -InputObject $qso -Property ComputerName, InstanceName, SqlInstance, Database, ActualState, DataFlushIntervalInSeconds, StatisticsCollectionIntervalInMinutes, MaxStorageSizeInMB, CurrentStorageSizeInMB, QueryCaptureMode, SizeBasedCleanupMode, StaleQueryThresholdInDays, MaxPlansPerQuery, WaitStatsCaptureMode
                } elseif ($server.VersionMajor -ge 15) {
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name CustomCapturePolicyExecutionCount -Value $QueryStoreOptions.CustomCapturePolicyExecutionCount
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name CustomCapturePolicyTotalCompileCPUTimeMS -Value $QueryStoreOptions.CustomCapturePolicyTotalCompileCPUTimeMS
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name CustomCapturePolicyTotalExecutionCPUTimeMS -Value $QueryStoreOptions.CustomCapturePolicyTotalExecutionCPUTimeMS
                    Add-Member -Force -InputObject $qso -MemberType NoteProperty -Name CustomCapturePolicyStaleThresholdHours -Value $QueryStoreOptions.CustomCapturePolicyStaleThresholdHours
                    Select-DefaultView -InputObject $qso -Property ComputerName, InstanceName, SqlInstance, Database, ActualState, DataFlushIntervalInSeconds, StatisticsCollectionIntervalInMinutes, MaxStorageSizeInMB, CurrentStorageSizeInMB, QueryCaptureMode, SizeBasedCleanupMode, StaleQueryThresholdInDays, MaxPlansPerQuery, WaitStatsCaptureMode, CustomCapturePolicyExecutionCount, CustomCapturePolicyTotalCompileCPUTimeMS, CustomCapturePolicyTotalExecutionCPUTimeMS, CustomCapturePolicyStaleThresholdHours
                }
            }
        }
    }
}