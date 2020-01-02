function Restore-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Restores databases from snapshots

    .DESCRIPTION
        Restores the database from the snapshot, discarding every modification made to the database
        NB: Restoring to a snapshot will result in every other snapshot of the same database to be dropped
        It also fixes some long-standing bugs in SQL Server when restoring from snapshots

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Restores from the last snapshot databases with this names only. You can pass either Databases or Snapshots

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER Snapshot
        Restores databases from snapshots with this names only. You can pass either Databases or Snapshots

    .PARAMETER InputObject
        Allows piping from other Snapshot commands

    .PARAMETER Force
        If restoring from a snapshot involves dropping any other snapshot, you need to explicitly
        use -Force to let this command delete the ones not involved in the restore process.
        Also, -Force will forcibly kill all running queries that prevent the restore process.

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                    try {
                        if ($Force) {
                            $null = Stop-DbaProcess -SqlInstance $server -Database $db.Name, $snap.Name -WarningAction SilentlyContinue
                        }

                        $null = $server.Query("USE master; RESTORE DATABASE [$($db.Name)] FROM DATABASE_SNAPSHOT='$($snap.Name)'")
                    } catch {
                        Stop-Function -Message "Failiure attempting to restore $db on $server" -ErrorRecord $_ -Continue
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