function Remove-DbaDbBackupRestoreHistory {
    <#
    .SYNOPSIS
        Removes backup and restore history records from MSDB database to prevent excessive growth

    .DESCRIPTION
        Removes backup and restore history records from MSDB database tables to prevent them from consuming excessive disk space and degrading performance. Over time, these history tables can grow substantially on busy SQL Server instances with frequent backup operations.

        Works in two modes: server-level cleanup removes records older than a specified retention period (default 30 days), while database-level cleanup removes the complete backup/restore history for specific databases. This is particularly useful when decommissioning databases or cleaning up after major maintenance operations.

        The backup and restore history tables reside in the MSDB database and include backupset, backupfile, restorehistory, and related system tables. Large history accumulations can impact backup operations, SSMS performance when viewing backup history, and overall MSDB database size.

        For production environments, consider scheduling regular cleanup using the sp_delete_backuphistory agent job from Ola Hallengren's SQL Server Maintenance Solution (https://ola.hallengren.com) rather than manual cleanup operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER KeepDays
        Specifies how many days of backup and restore history to retain when performing server-level cleanup. Records older than this period will be deleted from MSDB history tables.
        Use this for regular maintenance to prevent MSDB growth while preserving recent history for troubleshooting. Cannot be combined with Database parameter.

    .PARAMETER Database
        Specifies specific databases to completely remove all backup and restore history records regardless of age. Accepts multiple database names and wildcards.
        Use this when decommissioning databases or performing targeted cleanup after major maintenance operations. Cannot be combined with KeepDays parameter.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase to remove complete backup and restore history for those specific databases.
        Use this for pipeline operations when working with filtered database collections or when combining with other dbatools database commands.

    .OUTPUTS
        None

        This command performs cleanup operations on the MSDB database backup and restore history tables but does not return any objects to the pipeline. It modifies data through SMO methods (DeleteBackupHistory for server-level cleanup and DropBackupHistory for database-level cleanup).

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Delete, Backup, Restore, Database
        Author: IJeb Reitsma

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbBackupRestoreHistory

    .EXAMPLE
        PS C:\> Remove-DbaDbBackupRestoreHistory -SqlInstance sql2016

        Prompts for confirmation then deletes backup and restore history on SQL Server sql2016 older than 30 days (default period)

    .EXAMPLE
        PS C:\> Remove-DbaDbBackupRestoreHistory -SqlInstance sql2016 -KeepDays 100 -Confirm:$false

        Remove backup and restore history on SQL Server sql2016 older than 100 days. Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Remove-DbaDbBackupRestoreHistory -SqlInstance sql2016 -Database db1

        Prompts for confirmation then deletes all backup and restore history for database db1 on SQL Server sql2016

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 | Remove-DbaDbBackupRestoreHistory -WhatIf

        Remove complete backup and restore history for all databases on SQL Server sql2016
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$KeepDays,
        [string[]]$Database,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if (-not $KeepDays -and -not $Database) {
            $KeepDays = 30
        }
        $odt = (Get-Date).AddDays(-$KeepDays)
    }

    process {
        if ($KeepDays -and $Database) {
            Stop-Function -Message "KeepDays cannot be used with Database. When Database is specified, all backup/restore history for that database is deleted."
            return
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if (-not $Database) {
                try {
                    if ($Pscmdlet.ShouldProcess($server, "Remove backup/restore history before $($odt) for all databases")) {
                        # While this method is named DeleteBackupHistory, it also removes restore history
                        $server.DeleteBackupHistory($odt)
                        $server.Refresh()
                    }
                } catch {
                    Stop-Function -Message "Could not remove backup/restore history on $server" -Continue
                }
            } else {
                $InputObject += $server.Databases | Where-Object { $_.Name -in $Database }
            }
        }

        foreach ($db in $InputObject) {
            try {
                $servername = $db.Parent.Name
                if ($Pscmdlet.ShouldProcess("$db on $servername", "Remove complete backup/restore history")) {
                    # While this method is named DropBackupHistory, it also removes restore history
                    $db.DropBackupHistory()
                    $db.Refresh()
                }
            } catch {
                Stop-Function -Message "Could not remove backup/restore history for database $db on $servername" -Continue
            }
        }
    }
}