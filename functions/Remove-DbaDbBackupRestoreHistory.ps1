function Remove-DbaDbBackupRestoreHistory {
    <#
    .SYNOPSIS
        Reduces the size of the backup and restore history tables by deleting old entries for backup sets.

    .DESCRIPTION
        Reduces the size of the backup and restore history tables by deleting the entries for backup sets.

        Can be used at server level, in this case a retention period -KeepDays can be set (default is 30 days).
        Can also be used at database level, in this case the complete history for the database(s) is deleted.

        The backup and restore history tables reside in the msdb database.

        To periodically remove old data from backup and restore history tables it is recommended to schedule the agent job sp_delete_backuphistory from the
        SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER KeepDays
        The number of days of history to keep. Defaults to 30 days.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Delete
        Author: IJeb Reitsma

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbBackupRestoreHistory

    .EXAMPLE
        PS C:\> Remove-DbaDbBackupRestoreHistory -SqlInstance sql2016

        Prompts for confirmation then deletes backup and restore history on SQL Server sql2016 older than 30 days (default period)

        PS C:\> Remove-DbaDbBackupRestoreHistory -SqlInstance sql2016 -KeepDays 100 -Confirm:$false

        Remove backup and restore history on SQL Server sql2016 older than 100 days. Does not prompt for confirmation.

        PS C:\> Remove-DbaDbBackupRestoreHistory -SqlInstance sql2016 -Database db1

        Prompts for confirmation then deletes all backup and restore history for database db1 on SQL Server sql2016

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                    # While this method is named DeleteBackupHistory, it also removes restore history
                    $db.DropBackupHistory()
                    $db.Refresh()
                }
            } catch {
                Stop-Function -Message "Could not remove backup/restore history for database $db on $servername" -Continue
            }
        }
    }
}