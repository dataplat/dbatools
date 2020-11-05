function Get-DbaLastBackup {
    <#
    .SYNOPSIS
        Get date/time for last known backups of databases.

    .DESCRIPTION
        Retrieves and compares the date/time for the last known backups, as well as the creation date/time for the database.

        Default output includes columns Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more database(s) to exclude from processing.

    .PARAMETER EnableException
        If this switch is enabled exceptions will be thrown to the caller, which will need to perform its own exception processing. Otherwise, the function will try to catch the exception, interpret it and provide a friendly error message.

    .NOTES
        Tags: DisasterRecovery, Backup
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaLastBackup

    .EXAMPLE
        PS C:\> Get-DbaLastBackup -SqlInstance ServerA\sql987

        Returns a custom object displaying Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated

    .EXAMPLE
        PS C:\> Get-DbaLastBackup -SqlInstance ServerA\sql987

        Returns a custom object with Server name, Database name, and the date the last time backups were performed.

    .EXAMPLE
        PS C:\> Get-DbaLastBackup -SqlInstance ServerA\sql987 | Select-Object *

        Returns a custom object with Server name, Database name, and the date the last time backups were performed, and also recoverymodel and calculations on how long ago backups were taken and what the status is.

    .EXAMPLE
        PS C:\> Get-DbaLastBackup -SqlInstance ServerA\sql987 | Select-Object * | Out-Gridview

        Returns a gridview displaying ComputerName, InstanceName, SqlInstance, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, LastFullBackupIsCopyOnly, LastDiffBackupIsCopyOnly, LastLogBackupIsCopyOnly, DatabaseCreated, DaysSinceDbCreated, Status

    .EXAMPLE
        PS C:\> $MyInstances | Get-DbaLastBackup | Where-Object -FilterScript { $_.LastFullBackup.Date -lt (Get-Date).AddDays(-3) } | Format-Table -Property SqlInstance, Database, LastFullBackup

        Returns all databases on the given instances without a full backup in the last three days.
        Note that the property LastFullBackup is a custom object, with the subproperty Date of type datetime and therefore suitable for comparison with dates.

    .EXAMPLE
        PS C:\> Get-DbaLastBackup -SqlInstance ServerA\sql987 | Where-Object { $_.LastFullBackupIsCopyOnly -eq $true }

        Filters for the databases that had a copy_only full backup done as the last backup.
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
        function Get-DbaDateOrNull ($TimeSpan) {
            if ($TimeSpan -eq 0) {
                return $null
            }
            return $TimeSpan
        }
        $StartOfTime = [DbaTimeSpan](New-TimeSpan -Start ([datetime]0))
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases | Where-Object { $_.name -ne 'tempdb' }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }
            # Get-DbaDbBackupHistory -Last would make the job in one query but SMO's (and this) report the last backup of this type regardless of the chain
            $FullHistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $dbs.Name -LastFull -IncludeCopyOnly -Raw
            $DiffHistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $dbs.Name -LastDiff -IncludeCopyOnly -Raw
            $LogHistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $dbs.Name -LastLog -IncludeCopyOnly -Raw
            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                $LastFullBackup = ($FullHistory | Where-Object Database -EQ $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1).End
                if ($null -ne $LastFullBackup) {
                    $SinceFull_ = [DbaTimeSpan](New-TimeSpan -Start $LastFullBackup)
                } else {
                    $SinceFull_ = $StartOfTime
                }

                $LastFullBackupIsCopyOnly = ($FullHistory | Where-Object Database -EQ $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1).is_copy_only

                $LastDiffBackup = ($DiffHistory | Where-Object Database -EQ $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1).End
                if ($null -ne $LastDiffBackup) {
                    $SinceDiff_ = [DbaTimeSpan](New-TimeSpan -Start $LastDiffBackup)
                } else {
                    $SinceDiff_ = $StartOfTime
                }

                # LastDiffBackupIsCopyOnly is always false because copy_only is not allowed with differential backups: https://docs.microsoft.com/en-us/sql/t-sql/statements/backup-transact-sql
                # It is tempting to not include this property in the result object, however, it is low-cost to do so and makes the command more self-documenting.
                $LastDiffBackupIsCopyOnly = ($DiffHistory | Where-Object Database -EQ $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1).is_copy_only

                $LastLogBackup = ($LogHistory | Where-Object Database -EQ $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1).End
                if ($null -ne $LastLogBackup) {
                    $SinceLog_ = [DbaTimeSpan](New-TimeSpan -Start $LastLogBackup)
                } else {
                    $SinceLog_ = $StartOfTime
                }

                $LastLogBackupIsCopyOnly = ($LogHistory | Where-Object Database -EQ $db.Name | Sort-Object -Property End -Descending | Select-Object -First 1).is_copy_only

                $daysSinceDbCreated = (New-TimeSpan -Start $db.createDate).Days

                if ($daysSinceDbCreated -lt 1 -and $SinceFull_ -eq 0) {
                    $Status = 'New database, not backed up yet'
                } elseif ($SinceFull_.Days -gt 0 -and $SinceDiff_.Days -gt 0) {
                    $Status = 'No Full or Diff Back Up in the last day'
                } elseif ($db.RecoveryModel -eq "Full" -and $SinceLog_.Hours -gt 0) {
                    $Status = 'No Log Back Up in the last hour'
                } else {
                    $Status = 'OK'
                }

                $result = [PSCustomObject]@{
                    ComputerName             = $server.ComputerName
                    InstanceName             = $server.ServiceName
                    SqlInstance              = $server.DomainInstanceName
                    Database                 = $db.Name
                    RecoveryModel            = $db.RecoveryModel
                    LastFullBackup           = [DbaDateTime]$LastFullBackup
                    LastDiffBackup           = [DbaDateTime]$LastDiffBackup
                    LastLogBackup            = [DbaDateTime]$LastLogBackup
                    SinceFull                = Get-DbaDateOrNull -TimeSpan $SinceFull_
                    SinceDiff                = Get-DbaDateOrNull -TimeSpan $SinceDiff_
                    SinceLog                 = Get-DbaDateOrNull -TimeSpan $SinceLog_
                    LastFullBackupIsCopyOnly = $LastFullBackupIsCopyOnly
                    LastDiffBackupIsCopyOnly = $LastDiffBackupIsCopyOnly # always false per https://docs.microsoft.com/en-us/sql/t-sql/statements/backup-transact-sql See comments above.
                    LastLogBackupIsCopyOnly  = $LastLogBackupIsCopyOnly
                    DatabaseCreated          = $db.createDate
                    DaysSinceDbCreated       = $daysSinceDbCreated
                    Status                   = $status
                }

                Select-DefaultView -InputObject $result -Property ComputerName, InstanceName, SqlInstance, Database, LastFullBackup, LastDiffBackup, LastLogBackup
            }
        }
    }
}