function Get-DbaDbQueryStoreOption {
    <#
    .SYNOPSIS
        Get the Query Store configuration for Query Store enabled databases.

    .DESCRIPTION
        Retrieves and returns the Query Store configuration for every database that has the Query Store feature enabled.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.QueryStoreOptions

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

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
        $ExcludeDatabase += 'master', 'tempdb', "model"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 13
            } catch {
                Write-Message -Level Warning -Message "Can't connect to $instance. Moving on."
                continue
            }

            # We have to exclude all the system databases since they cannot have the Query Store feature enabled
            $dbs = Get-DbaDatabase -SqlInstance $server -ExcludeDatabase $ExcludeDatabase -Database $Database | Where-Object IsAccessible

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.Name) on $instance"
                $qso = $db.QueryStoreOptions

                if ($server.VersionMajor -eq 14) {
                    $QueryStoreOptions = $db.Query("SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode FROM sys.database_query_store_options;", $db.Name)
                } elseif ($server.VersionMajor -ge 15) {
                    $QueryStoreOptions = $db.Query("SELECT max_plans_per_query AS MaxPlansPerQuery, wait_stats_capture_mode_desc AS WaitStatsCaptureMode, capture_policy_execution_count AS CustomCapturePolicyExecutionCount, capture_policy_stale_threshold_hours AS CustomCapturePolicyStaleThresholdHours, capture_policy_total_compile_cpu_time_ms AS CustomCapturePolicyTotalCompileCPUTimeMS, capture_policy_total_execution_cpu_time_ms AS CustomCapturePolicyTotalExecutionCPUTimeMS FROM sys.database_query_store_options;", $db.Name)
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