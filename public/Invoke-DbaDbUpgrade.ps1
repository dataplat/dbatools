function Invoke-DbaDbUpgrade {
    <#
    .SYNOPSIS
        Upgrades database compatibility level and performs post-upgrade maintenance tasks

    .DESCRIPTION
        Performs the essential steps needed after upgrading SQL Server or moving databases to a newer instance. Updates database compatibility level to match the hosting SQL Server version and sets target recovery time to 60 seconds for SQL Server 2016 and newer.

        Executes critical post-upgrade maintenance including DBCC CHECKDB with DATA_PURITY to detect data corruption, DBCC UPDATEUSAGE to correct page counts, sp_updatestats to refresh statistics, and sp_refreshview to update all user views with new metadata. This automates the manual checklist DBAs typically follow after SQL Server upgrades to ensure databases function optimally on the new version.

        Based on https://thomaslarock.com/2014/06/upgrading-to-sql-server-2014-a-dozen-things-to-check/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        Specifies which databases to upgrade and run post-upgrade maintenance tasks on. Accepts wildcards for pattern matching.
        Use this when you need to target specific databases rather than processing all user databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the upgrade process when using -AllUserDatabases. Accepts wildcards for pattern matching.
        Useful for skipping system-critical databases or those with special maintenance windows during bulk upgrade operations.

    .PARAMETER AllUserDatabases
        Processes all user databases on the instance, excluding system databases. Cannot be used with -Database parameter.
        Use this for instance-wide upgrades after SQL Server version changes or when standardizing all databases to current compatibility levels.

    .PARAMETER Force
        Runs all maintenance tasks even on databases already at the correct compatibility level and target recovery time.
        Use this when you need to ensure CHECKDB, UPDATEUSAGE, statistics updates, and view refreshes run regardless of compatibility status.

    .PARAMETER NoCheckDb
        Skips the DBCC CHECKDB with DATA_PURITY validation step during the upgrade process.
        Use this when you've recently run integrity checks or need to reduce upgrade time, though this removes corruption detection from the process.

    .PARAMETER NoUpdateUsage
        Skips the DBCC UPDATEUSAGE step that corrects inaccuracies in page and row count information.
        Use this when you're confident space usage statistics are accurate or need to minimize upgrade time for very large databases.

    .PARAMETER NoUpdateStats
        Skips running sp_updatestats to refresh all user table statistics with current data distribution.
        Use this when statistics were recently updated or when you have a separate statistics maintenance plan in place.

    .PARAMETER NoRefreshView
        Skips executing sp_refreshview on all user views to update their metadata for the new SQL Server version.
        Use this when you have no views or prefer to refresh view metadata manually to avoid potential view compilation issues.

    .PARAMETER InputObject
        Accepts database objects from the pipeline, typically from Get-DbaDatabase output. Cannot be used with -Database or -AllUserDatabases.
        Use this for targeted upgrades based on complex filtering criteria or when integrating with other dbatools commands in a pipeline.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Update database" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Shrink, Database
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbUpgrade

    .OUTPUTS
        PSCustomObject

        Returns one object per database processed with detailed information about each upgrade operation performed.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: Name of the database that was upgraded
        - OriginalCompatibility: Original database compatibility level before upgrade (e.g., "100", "110", "140")
        - CurrentCompatibility: New database compatibility level after upgrade (e.g., "100", "110", "140")
        - Compatibility: Result status of compatibility level update; values: version number if updated, "No change" if already correct, "Fail" if update failed
        - TargetRecoveryTime: Result of target recovery time update; values: 60 if set to 60 seconds, "No change" if already 60 or SQL Server version < 2016, "Fail" if update failed
        - DataPurity: Result of DBCC CHECKDB DATA_PURITY; values: "Success" if completed, "Fail" if failed, omitted if -NoCheckDb is specified
        - UpdateUsage: Result of DBCC UPDATEUSAGE; values: "Success" if completed, "Fail" if failed, "Skipped" if -NoUpdateUsage is specified
        - UpdateStats: Result of sp_updatestats; values: "Success" if completed, "Fail" if failed, "Skipped" if -NoUpdateStats is specified
        - RefreshViews: Result of sp_refreshview on all user views; values: "Success" if all refreshed, "Fail" if any failed, "Skipped" if -NoRefreshView is specified

    .EXAMPLE
        PS C:\> Invoke-DbaDbUpgrade -SqlInstance PRD-SQL-MSD01 -Database Test

        Runs the below processes against the databases
        -- Puts compatibility of database to level of SQL Instance
        -- Changes the target recovery time to the new default of 60 seconds (for SQL Server 2016 and newer)
        -- Runs CHECKDB DATA_PURITY
        -- Runs DBCC UPDATESUSAGE
        -- Updates all users statistics
        -- Runs sp_refreshview against every view in the database

    .EXAMPLE
        PS C:\> Invoke-DbaDbUpgrade -SqlInstance PRD-SQL-INT01 -Database Test -NoRefreshView

        Runs the upgrade command skipping the sp_refreshview update on all views

    .EXAMPLE
        PS C:\> Invoke-DbaDbUpgrade -SqlInstance PRD-SQL-INT01 -Database Test -Force

        If database Test is already at the correct compatibility, runs every necessary step

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 | Out-GridView -Passthru | Invoke-DbaDbUpgrade

        Get only specific databases using GridView and pass those to Invoke-DbaDbUpgrade

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$NoCheckDb,
        [switch]$NoUpdateUsage,
        [switch]$NoUpdateStats,
        [switch]$NoRefreshView,
        [switch]$AllUserDatabases,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        if (Test-Bound -not 'SqlInstance', 'InputObject') {
            Write-Message -Level Warning -Message "You must specify either a SQL instance or pipe a database collection"
            continue
        }

        if (Test-Bound -not 'Database', 'InputObject', 'ExcludeDatabase', 'AllUserDatabases') {
            Write-Message -Level Warning -Message "You must explicitly specify a database. Use -Database, -ExcludeDatabase, -AllUserDatabases or pipe a database collection"
            continue
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $InputObject += $server.Databases | Where-Object IsAccessible
        }

        $InputObject = $InputObject | Where-Object { $_.IsSystemObject -eq $false }
        if ($Database) {
            $InputObject = $InputObject | Where-Object Name -In $Database
        }
        if ($ExcludeDatabase) {
            $InputObject = $InputObject | Where-Object Name -NotIn $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            # create objects to use in updates
            $server = $db.Parent
            $serverVersion = $server.VersionMajor
            Write-Message -Level Verbose -Message "SQL Server is using Version: $serverVersion"

            $dbLevel = $db.CompatibilityLevel
            $serverLevel = [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]"Version$($serverVersion)0"
            $levelOk = $dbLevel -eq $serverLevel
            $timeOk = if ($serverVersion -ge 13 -and $db.TargetRecoveryTime -ne 60) { $false } else { $true }

            if (-not $Force) {
                # skip over databases at the correct level and correct target recovery time, unless -Force
                if ($levelOk -and $timeOk) {
                    Write-Message -Level VeryVerbose -Message "Skipping $db because compatibility is at the correct level and target recovery time is correct. Use -Force if you want to run all the additional steps."
                    continue
                }
            }

            Write-Message -Level Verbose -Message "Updating $db compatibility to SQL Instance level"
            if (-not $levelOk) {
                If ($Pscmdlet.ShouldProcess($server, "Updating $db compatibility on $server from $dbLevel to $serverLevel")) {
                    try {
                        $db.CompatibilityLevel = $serverLevel
                        $db.Alter()
                        $CompatibilityResult = $serverLevel.ToString().Replace('Version', '')
                    } catch {
                        Write-Message -Level Warning -Message "Failed run Compatibility Upgrade" -ErrorRecord $_ -Target $instance
                        $CompatibilityResult = "Fail"
                    }
                }
            } else {
                $CompatibilityResult = "No change"
            }

            Write-Message -Level Verbose -Message "Updating $db target recovery time to 60 seconds on SQL Server 2016 or newer"
            if (-not $timeOk) {
                If ($Pscmdlet.ShouldProcess($server, "Updating $db target recovery time on $server from $($db.TargetRecoveryTime) seconds to 60 seconds")) {
                    try {
                        $db.TargetRecoveryTime = 60
                        $db.Alter()
                        $targetRecoveryTimeResult = 60
                    } catch {
                        Write-Message -Level Warning -Message "Failed to change target recovery time" -ErrorRecord $_ -Target $instance
                        $targetRecoveryTimeResult = "Fail"
                    }
                }
            } else {
                $targetRecoveryTimeResult = "No change"
            }

            if (!($NoCheckDb)) {
                Write-Message -Level Verbose -Message "Updating $db with DBCC CHECKDB DATA_PURITY"
                If ($Pscmdlet.ShouldProcess($server, "Updating $db with DBCC CHECKDB DATA_PURITY")) {
                    $tsqlCheckDB = "DBCC CHECKDB ('$($db.Name)') WITH DATA_PURITY, NO_INFOMSGS"
                    try {
                        $db.ExecuteNonQuery($tsqlCheckDB)
                        $DataPurityResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed run DBCC CHECKDB with DATA_PURITY on $db" -ErrorRecord $_ -Target $instance
                        $DataPurityResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignoring CHECKDB DATA_PURITY"
            }

            if (!($NoUpdateUsage)) {
                Write-Message -Level Verbose -Message "Updating $db with DBCC UPDATEUSAGE"
                If ($Pscmdlet.ShouldProcess($server, "Updating $db with DBCC UPDATEUSAGE")) {
                    $tsqlUpdateUsage = "DBCC UPDATEUSAGE ($db) WITH NO_INFOMSGS;"
                    try {
                        $db.ExecuteNonQuery($tsqlUpdateUsage)
                        $UpdateUsageResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed to run DBCC UPDATEUSAGE on $db" -ErrorRecord $_ -Target $instance
                        $UpdateUsageResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignore DBCC UPDATEUSAGE"
                $UpdateUsageResult = "Skipped"
            }

            if (!($NoUpdatestats)) {
                Write-Message -Level Verbose -Message "Updating $db statistics"
                If ($Pscmdlet.ShouldProcess($server, "Updating $db statistics")) {
                    $tsqlStats = "EXEC sp_updatestats;"
                    try {
                        $db.ExecuteNonQuery($tsqlStats)
                        $UpdateStatsResult = "Success"
                    } catch {
                        Write-Message -Level Warning -Message "Failed to run sp_updatestats on $db" -ErrorRecord $_ -Target $instance
                        $UpdateStatsResult = "Fail"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignoring sp_updatestats"
                $UpdateStatsResult = "Skipped"
            }

            if (!($NoRefreshView)) {
                Write-Message -Level Verbose -Message "Refreshing $db Views"
                $dbViews = $db.Views | Where-Object IsSystemObject -eq $false
                $RefreshViewResult = "Success"
                foreach ($dbview in $dbviews) {
                    $viewName = $dbView.Name
                    $viewSchema = $dbView.Schema
                    $fullName = $viewSchema + "." + $viewName

                    $tsqlupdateView = "EXECUTE sp_refreshview N'$fullName';  "

                    If ($Pscmdlet.ShouldProcess($server, "Refreshing view $fullName on $db")) {
                        try {
                            $db.ExecuteNonQuery($tsqlupdateView)
                        } catch {
                            Write-Message -Level Warning -Message "Failed update view $fullName on $db" -ErrorRecord $_ -Target $instance
                            $RefreshViewResult = "Fail"
                        }
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Ignore View Refreshes"
                $RefreshViewResult = "Skipped"
            }

            If ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                $db.Refresh()

                [PSCustomObject]@{
                    ComputerName          = $server.ComputerName
                    InstanceName          = $server.ServiceName
                    SqlInstance           = $server.DomainInstanceName
                    Database              = $db.name
                    OriginalCompatibility = $dbLevel.ToString().Replace('Version', '')
                    CurrentCompatibility  = $db.CompatibilityLevel.ToString().Replace('Version', '')
                    Compatibility         = $CompatibilityResult
                    TargetRecoveryTime    = $targetRecoveryTimeResult
                    DataPurity            = $DataPurityResult
                    UpdateUsage           = $UpdateUsageResult
                    UpdateStats           = $UpdateStatsResult
                    RefreshViews          = $RefreshViewResult
                }
            }
        }
    }
}