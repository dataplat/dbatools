function Set-DbaQueryStoreConfig {
    <#
		.SYNOPSIS
			Configure Query Store settings for a specific or multiple databases.

		.DESCRIPTION
			Configure Query Store settings for a specific or multiple databases.

		.PARAMETER SqlInstance
			The SQL Server that you're connecting to.

		.PARAMETER SqlCredential
			SqlCredential object used to connect to the SQL Server as a different user.

		.PARAMETER Database
			The database(s) to process - this list is auto populated from the server. If unspecified, all databases will be processed.

		.PARAMETER ExcludeDatabase
			The database(s) to exclude - this list is auto populated from the server

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

		.PARAMETER WhatIf
			Shows what would happen if the command were to run

		.PARAMETER Confirm
			Prompts for confirmation of every step. For example:

			Are you sure you want to perform this action?
			Performing the operation "Changing Desired State" on target "pubs on SQL2016\VNEXT".
			[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: QueryStore
			Original Author: Enrico van de Laar ( @evdlaar )

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Set-QueryStoreConfig

		.EXAMPLE
			Set-DbaQueryStoreConfig -SqlInstance ServerA\SQL -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode All -CleanupMode Auto -StaleQueryThreshold 100 -AllDatabases

			Configure the Query Store settings for all user databases in the ServerA\SQL Instance.

		.EXAMPLE
			Set-DbaQueryStoreConfig -SqlInstance ServerA\SQL -FlushInterval 600

			Only configure the FlushInterval setting for all Query Store databases in the ServerA\SQL Instance.

		.EXAMPLE
			Set-DbaQueryStoreConfig -SqlInstance ServerA\SQL -Database AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

			Configure the Query Store settings for the AdventureWorks database in the ServerA\SQL Instance.

		.EXAMPLE
			Set-DbaQueryStoreConfig -SqlInstance ServerA\SQL -Exclude AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

			Configure the Query Store settings for all user databases except the AdventureWorks database in the ServerA\SQL Instance.
	#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
		[object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [ValidateSet('ReadWrite', 'ReadOnly', 'Off')]
        [string[]]$State,
        [int64]$FlushInterval,
        [int64]$CollectionInterval,
        [int64]$MaxSize,
        [ValidateSet('Auto', 'All')]
        [string[]]$CaptureMode,
        [ValidateSet('Auto', 'Off')]
        [string[]]$CleanupMode,
        [int64]$StaleQueryThreshold,
		[switch]$Silent
    )

    process {
        if (!$Database -and !$ExcludeDatabase -and !$AllDatabases) {
            Stop-Function -Message "You must specify a database(s) to execute against using either -Database, -ExcludeDatabase or -AllDatabases"
            return
        }

        if (!$State -and !$FlushInterval -and !$CollectionInterval -and !$MaxSize -and !$CaptureMode -and !$CleanupMode -and !$StaleQueryThreshold) {
            Stop-Function -Message "You must specify something to change."
            return
        }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential

            }
            catch {
                Stop-Function -Message "Can't connect to $instance. Moving on." -Category InvalidOperation -InnerErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -lt 13) {
                Stop-Function -Message "The SQL Server Instance ($instance) has a lower SQL Server version than SQL Server 2016. Skipping server."
                continue
            }

            # We have to exclude all the system databases since they cannot have the Query Store feature enabled
            $dbs = Get-DbaDatabase -SqlInstance $instance -NoSystemDb

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabas
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db on server $instance is not accessible. Skipping database."
                    Continue
                }

                if ($State) {
                    if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing DesiredState to $state")) {
                        $db.QueryStoreOptions.DesiredState = $State
                    }
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

                # Alter the Query Store Configuration
                if ($Pscmdlet.ShouldProcess("$db on $instance", "Altering Query Store configuration on database")) {
                    try {
                        $db.QueryStoreOptions.Alter()
                        $db.Refresh()
                    }
                    catch {
                        Stop-Function -Message "Could not modify configuration." -Category InvalidOperation -InnerErrorRecord $_ -Target $db -Continue
                    }
                }

                if ($Pscmdlet.ShouldProcess("$db on $instance", "Getting results from Get-DbaQueryStoreConfig")) {
                    # Display resulting changes
                    Get-DbaQueryStoreConfig -SqlInstance $server -Database $db.name -Verbose:$false
                }
            }
        }
    }
}

