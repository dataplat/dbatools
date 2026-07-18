function Restore-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Restores SQL Server databases from database snapshots, reverting to the snapshot's point-in-time state

    .DESCRIPTION
        Restores SQL Server databases to their exact state when a database snapshot was created, discarding all changes made since that point. This is particularly useful for quickly reverting development databases after testing, rolling back problematic changes, or returning to a known good state without restoring from backup files.

        The function uses SQL Server's RESTORE DATABASE FROM DATABASE_SNAPSHOT command and automatically handles SQL Server's requirement that all other snapshots of the same database be dropped before restoration. It also fixes a SQL Server bug where log file growth settings get reset to their defaults during snapshot restoration.

        When Force is specified, the command will terminate active connections to both the target database and snapshot to ensure the restore operation completes successfully.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to restore from their most recent snapshots. Accepts multiple database names and wildcards for pattern matching.
        Use this when you want to restore specific databases to their snapshot state rather than working with snapshot names directly.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from being restored when using wildcard patterns or restoring multiple databases.
        Helpful when you want to restore most databases from snapshots but skip certain critical production databases.

    .PARAMETER Snapshot
        Specifies the exact snapshot names to restore from, giving you precise control over which snapshot is used for each database.
        Use this when you need to restore from specific snapshots rather than automatically using the most recent ones.

    .PARAMETER InputObject
        Accepts snapshot objects from other dbatools commands like Get-DbaDbSnapshot through the PowerShell pipeline.
        This enables you to filter and select specific snapshots before restoring, such as using Out-GridView for interactive selection.

    .PARAMETER Force
        Automatically drops other snapshots of the same database that would prevent the restore operation, as required by SQL Server.
        Also terminates active connections to both the target database and snapshot to ensure the restore completes successfully.
        Required when multiple snapshots exist for the database being restored or when active sessions could block the operation.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Snapshot, Backup, Restore, Database
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Restore-DbaDbSnapshot

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Database

        Returns one Database object for each database that was successfully restored from a snapshot. The returned object represents the state of the database after the restore operation completed and log file growth settings were restored to their pre-snapshot values.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: Database name
        - Status: Current database status (Normal, Suspect, Offline, etc.)
        - IsAccessible: Boolean indicating if the database is currently accessible
        - RecoveryModel: Database recovery model (Full, Simple, BulkLogged)
        - Owner: Database owner login name

        Additional properties available from the SMO Database object:
        - Size: Current size of the database in megabytes
        - CreateDate: DateTime when the database was created
        - LastBackupDate: DateTime of the most recent backup
        - LastDiffBackup: DateTime of the most recent differential backup
        - LastLogBackup: DateTime of the most recent transaction log backup
        - Collation: Database collation setting
        - CompatibilityLevel: Database compatibility level

        All properties from the base SMO Database object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Restore-DbaDbSnapshot -SqlInstance sql2014 -Database HR, Accounting

        Restores HR and Accounting databases using the latest snapshot available

    .EXAMPLE
        PS C:\> Restore-DbaDbSnapshot -SqlInstance sql2014 -Database HR -Force

        Restores HR database from latest snapshot and kills any active connections in the database on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaDbSnapshot -SqlInstance sql2016 -Database HR | Restore-DbaDbSnapshot -Force

        Restores HR database from latest snapshot and kills any active connections in the database on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaDbSnapshot -SqlInstance sql2016 | Out-GridView -PassThru | Restore-DbaDbSnapshot

        Allows the selection of snapshots on sql2016 to restore

    .EXAMPLE
        PS C:\> Restore-DbaDbSnapshot -SqlInstance sql2014 -Snapshot HR_snap_20161201, Accounting_snap_20161101

        Restores databases from snapshots named HR_snap_20161201 and Accounting_snap_20161101

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$Snapshot,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (-not $Snapshot -and -not $Database -and -not $ExcludeDatabase -and -not $InputObject) {
            Stop-Function -Message "You must specify either -Snapshot (to restore from) or -Database/-ExcludeDatabase (to restore to) or pipe in a snapshot"
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $InputObject += Get-DbaDbSnapshot -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -Snapshot $Snapshot | Sort-Object CreateDate -Descending

            if ($Snapshot) {
                # Restore databases from these snapshots
                Write-Message -Level Verbose -Message "Selected only snapshots"
                $dbs = $InputObject | Where-Object { $Snapshot -contains $_.Name }
                $baseDatabases = $dbs | Select-Object -ExpandProperty DatabaseSnapshotBaseName | Get-Unique
                if ($baseDatabases.Count -ne $Snapshot.Count -and $dbs.Count -ne 0) {
                    Stop-Function -Message "Failure. Multiple snapshots selected for the same database" -Continue
                }
            }
        }

        foreach ($snap in $InputObject) {
            # In the event someone passed -Database and it got all the snaps, most of which were dropped by the first
            if ($snap.Parent) {
                $server = $snap.Parent

                if (-not $snap.IsDatabaseSnapshot) {
                    Stop-Function -Continue -Message "$snap on $server is not a valid snapshot"
                }

                if (-not ($snap.IsAccessible)) {
                    Stop-Function -Message "Database $snap is not accessible on $($snap.Parent)." -Continue
                }

                $othersnaps = $server.Databases | Where-Object { $_.DatabaseSnapshotBaseName -eq $snap.DatabaseSnapshotBaseName -and $_.Name -ne $snap.Name }

                $db = $server.Databases | Where-Object Name -eq $snap.DatabaseSnapshotBaseName
                $loginfo = $db.LogFiles | Select-Object Id, Size, Growth, GrowthType

                if (($snap | Where-Object FileGroupType -eq 'FileStreamDataFileGroup')) {
                    Stop-Function -Message "Database $snap on $server has FileStream group(s). You cannot restore from snapshots" -Continue
                }

                if ($othersnaps -and -not $force) {
                    Stop-Function -Message "The restore process for $db from $snap needs to drop other snapshots on $db. Use -Force if you want to drop these snapshots" -Continue
                }

                if ($Pscmdlet.ShouldProcess($server, "Remove other db snapshots for $db")) {
                    try {
                        $null = $othersnaps | Remove-DbaDatabase -Confirm:$false -EnableException
                    } catch {
                        Stop-Function -Message "Failed to remove other snapshots for $db on $server" -ErrorRecord $_ -Continue
                    }
                }

                # Need a proper restore now
                if ($Pscmdlet.ShouldProcess($server, "Restore db $db from $snap")) {
                    $maxRetries = 3
                    $retryCount = 0
                    $restoreSuccess = $false

                    while (-not $restoreSuccess -and $retryCount -lt $maxRetries) {
                        try {
                            if ($Force) {
                                $null = Stop-DbaProcess -SqlInstance $server -Database $db.Name, $snap.Name -WarningAction SilentlyContinue
                            }

                            $null = $server.Query("USE master; RESTORE DATABASE [$($db.Name)] FROM DATABASE_SNAPSHOT = '$($snap.Name)'")
                            $restoreSuccess = $true
                        } catch {
                            # Check if this is a deadlock error (error 1205)
                            if ($_.Exception.InnerException.Number -eq 1205) {
                                $retryCount++
                                if ($retryCount -lt $maxRetries) {
                                    $waitSeconds = [Math]::Pow(2, $retryCount)
                                    Write-Message -Level Verbose -Message "Deadlock detected during restore of $db on $server. Retrying in $waitSeconds seconds (attempt $retryCount of $maxRetries)"
                                    Start-Sleep -Seconds $waitSeconds
                                } else {
                                    Stop-Function -Message "Failiure attempting to restore $db on $server after $maxRetries attempts due to deadlock" -ErrorRecord $_ -Continue
                                }
                            } else {
                                Stop-Function -Message "Failiure attempting to restore $db on $server" -ErrorRecord $_ -Continue
                                break
                            }
                        }
                    }

                    if (-not $restoreSuccess) {
                        continue
                    }
                }

                # Comparing sizes before and after, need to refresh to see if size
                foreach ($log in $db.LogFiles) {
                    $log.Refresh()
                }

                foreach ($log in $db.LogFiles) {
                    $matching = $loginfo | Where-Object ID -eq $log.ID
                    $changeflag = 0
                    foreach ($prop in @('Size', 'Growth', 'Growth', 'GrowthType')) {
                        if ($matching.$prop -ne $log.$prop) {
                            $changeflag = 1
                            $log.$prop = $matching.$prop
                        }
                    }
                    if ($changeflag -ne 0) {
                        Write-Message -Level Verbose -Message "Restoring original settings for log file"
                        $log.Alter()
                    }
                }

                Write-Message -Level Verbose -Message "Restored. Remember to take a backup now, and also to remove the snapshot if not needed."
                Get-DbaDatabase -SqlInstance $server -Database $db.Name
            }
        }
    }
}