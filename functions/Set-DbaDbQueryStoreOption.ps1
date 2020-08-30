function Set-DbaDbQueryStoreOption {
    <#
    .SYNOPSIS
        Configure Query Store settings for a specific or multiple databases.

    .DESCRIPTION
        Configure Query Store settings for a specific or multiple databases.

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

    .PARAMETER AllDatabases
        Run command against all user databases

    .PARAMETER State
        Set the state of the Query Store. Valid options are "ReadWrite", "ReadOnly" and "Off".

    .PARAMETER FlushInterval
        Set the flush to disk interval of the Query Store in seconds.

    .PARAMETER CollectionInterval
        Set the runtime statistics collection interval of the Query Store in minutes.

    .PARAMETER MaxSize
        Set the maximum size of the Query Store in MB.

    .PARAMETER CaptureMode
        Set the query capture mode of the Query Store. Valid options are "Auto" and "All".

    .PARAMETER CleanupMode
        Set the query cleanup mode policy. Valid options are "Auto" and "Off".

    .PARAMETER StaleQueryThreshold
        Set the stale query threshold in days.

    .PARAMETER MaxPlansPerQuery
        Set the max plans per query captured and kept.

    .PARAMETER WaitStatsCaptureMode
        Set wait stats capture on or off.

    .PARAMETER CustomCapturePolicyExecutionCount
        Set the custom capture policy execution count. Only available in SQL Server 2019 and above.

    .PARAMETER CustomCapturePolicyTotalCompileCPUTimeMS
        Set the custom capture policy total compile CPU time. Only available in SQL Server 2019 and above.

    .PARAMETER CustomCapturePolicyTotalExecutionCPUTimeMS
        Set the custom capture policy total execution CPU time. Only available in SQL Server 2019 and above.

    .PARAMETER CustomCapturePolicyStaleThresholdHours
        Set the custom capture policy stale threshold. Only available in SQL Server 2019 and above.

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
        Author: Enrico van de Laar (@evdlaar) | Tracy Boggiano ( @TracyBoggiano )

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 13
            } catch {
                Stop-Function -Message "Can't connect to $instance. Moving on." -Category InvalidOperation -InnerErrorRecord $_ -Target $instance -Continue
            }

            if ($CaptureMode -contains "Custom" -and $server.VersionMajor -lt 15) {
                Stop-Function -Message "Custom capture mode can onlly be set in SQL Server 2019 and above" -Continue
            }

            if (($CustomCapturePolicyExecutionCount -or $CustomCapturePolicyTotalCompileCPUTimeMS -or $CustomCapturePolicyTotalExecutionCPUTimeMS -or $CustomCapturePolicyStaleThresholdHours) -and $server.VersionMajor -lt 15) {
                Write-Message -Level Warning -Message "Custom Capture Policies can only be set in SQL Server 2019 and above. These options will be skipped for $instance"
            }

            # We have to exclude all the system databases since they cannot have the Query Store feature enabled
            $dbs = Get-DbaDatabase -SqlInstance $server -ExcludeDatabase $ExcludeDatabase -Database $Database | Where-Object IsAccessible

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
                            $query += "ALTER DATABASE $db SET QUERY_STORE = ON (MAX_PLANS_PER_QUERY = $($MaxPlansPerQuery)); "
                        }
                    }

                    if ($WaitStatsCaptureMode) {
                        if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing WaitStatsCaptureMode to $($WaitStatsCaptureMode)")) {
                            if ($WaitStatsCaptureMode -eq "ON" -or $WaitStatsCaptureMode -eq "OFF") {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON (WAIT_STATS_CAPTURE_MODE = $($WaitStatsCaptureMode)); "
                            }
                        }
                    }
                }

                if ($server.VersionMajor -ge 15) {
                    if ($db.QueryStoreOptions.QueryCaptureMode -eq "CUSTOM") {
                        if ($CustomCapturePolicyStaleThresholdHours) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyStaleThresholdHours to $($CustomCapturePolicyStaleThresholdHours)")) {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON ( QUERY_CAPTURE_POLICY = ( STALE_CAPTURE_POLICY_THRESHOLD = $($CustomCapturePolicyStaleThresholdHours))); "
                            }
                        }

                        if ($CustomCapturePolicyExecutionCount) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyExecutionCount to $($CustomCapturePolicyExecutionCount)")) {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (EXECUTION_COUNT = $($CustomCapturePolicyExecutionCount))); "
                            }
                        }
                        if ($CustomCapturePolicyTotalCompileCPUTimeMS) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyTotalCompileCPUTimeMS to $($CustomCapturePolicyTotalCompileCPUTimeMS)")) {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (TOTAL_COMPILE_CPU_TIME_MS = $($CustomCapturePolicyTotalCompileCPUTimeMS))); "
                            }
                        }

                        if ($CustomCapturePolicyTotalExecutionCPUTimeMS) {
                            if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing CustomCapturePolicyTotalExecutionCPUTimeMS to $($CustomCapturePolicyTotalExecutionCPUTimeMS)")) {
                                $query += "ALTER DATABASE $db SET QUERY_STORE = ON (QUERY_CAPTURE_POLICY = (TOTAL_EXECUTION_CPU_TIME_MS = $($CustomCapturePolicyTotalExecutionCPUTimeMS))); "
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