function Get-DbaLastBackup {
    <#
        .SYNOPSIS
            Get date/time for last known backups of databases.

        .DESCRIPTION
            Retrieves and compares the date/time for the last known backups, as well as the creation date/time for the database.

            Default output includes columns Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated.

        .PARAMETER SqlInstance
            The SQL Server instance to connect to.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            Specifies one or more database(s) to process. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies one or more database(s) to exclude from processing.

        .PARAMETER EnableException
            If this switch is enabled exceptions will be thrown to the caller, which will need to perform its own exception processing. Otherwise, the function will try to catch the exception, interpret it and provide a friendly error message.

        .NOTES
            Tags: DisasterRecovery, Backup
            Author: Klaas Vandenberghe ( @PowerDBAKlaas )

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaLastBackup

        .EXAMPLE
            Get-DbaLastBackup -SqlInstance ServerA\sql987

            Returns a custom object displaying Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated

        .EXAMPLE
            Get-DbaLastBackup -SqlInstance ServerA\sql987

            Returns a custom object with Server name, Database name, and the date the last time backups were performed.

        .EXAMPLE
            Get-DbaLastBackup -SqlInstance ServerA\sql987 | Select *

            Returns a custom object with Server name, Database name, and the date the last time backups were performed, and also recoverymodel and calculations on how long ago backups were taken and what the status is.

        .EXAMPLE
            Get-DbaLastBackup -SqlInstance ServerA\sql987 | Select * | Out-Gridview

            Returns a gridview displaying Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Write-Message -Level Warning -Message "Can't connect to $instance"
                Continue
            }

            $dbs = $server.Databases | Where-Object { $_.name -ne 'tempdb' }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                $result = $null
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db on server $instance is not accessible. Skipping database."
                    Continue
                }
                # To avoid complicated manipulations on datetimes depending on locale settings and culture,
                # dates are compared to 0, which represents 1/01/0001 0:00:00
                $SinceFull = if ($db.LastBackupdate -eq 0) {
                    [String]::Empty
                }
                else {
                    (New-TimeSpan -Start $db.LastBackupdate).Tostring()
                }
                $SinceFull = if ($db.LastBackupdate -eq 0) {
                    [String]::Empty
                }
                else {
                    $SinceFull.split('.')[0 .. ($SinceFull.split('.').count - 2)] -join ' days '
                }

                $SinceDiff = if ($db.LastDifferentialBackupDate -eq 0) {
                    [String]::Empty
                }
                else {
                    (New-TimeSpan -Start $db.LastDifferentialBackupDate).Tostring()
                }
                $SinceDiff = if ($db.LastDifferentialBackupDate -eq 0) {
                    [String]::Empty
                }
                else {
                    $SinceDiff.split('.')[0 .. ($SinceDiff.split('.').count - 2)] -join ' days '
                }

                $SinceLog = if ($db.LastLogBackupDate -eq 0) {
                    [String]::Empty
                }
                else {
                    (New-TimeSpan -Start $db.LastLogBackupDate).Tostring()
                }
                $SinceLog = if ($db.LastLogBackupDate -eq 0) {
                    [String]::Empty
                }
                else {
                    $SinceLog.split('.')[0 .. ($SinceLog.split('.').count - 2)] -join ' days '
                }

                $daysSinceDbCreated = (New-TimeSpan -Start $db.createDate).Days

                if ($daysSinceDbCreated -lt 1 -and $db.LastBackupDate -eq 0) {
                    $Status = 'New database, not backed up yet'
                }
                elseif ((New-TimeSpan -Start $db.LastBackupDate).Days -gt 0 -and (New-TimeSpan -Start $db.LastDifferentialBackupDate).Days -gt 0) {
                    $Status = 'No Full or Diff Back Up in the last day'
                }
                elseif ($db.RecoveryModel -eq "Full" -and (New-TimeSpan -Start $db.LastLogBackupDate).Hours -gt 0) {
                    $Status = 'No Log Back Up in the last hour'
                }
                else {
                    $Status = 'OK'
                }

                $result = [PSCustomObject]@{
                    ComputerName       = $server.NetName
                    InstanceName       = $server.ServiceName
                    SqlInstance        = $server.DomainInstanceName
                    Database           = $db.name
                    RecoveryModel      = $db.recoverymodel
                    LastFullBackup     = if ($db.LastBackupdate -eq 0) { $null } else { [DbaDateTime]$db.LastBackupdate}
                    LastDiffBackup     = if ($db.LastDifferentialBackupDate -eq 0) { $null } else { [DbaDateTime]$db.LastDifferentialBackupDate }
                    LastLogBackup      = if ($db.LastLogBackupDate -eq 0) { $null } else { [DbaDateTime]$db.LastLogBackupDate }
                    SinceFull          = $SinceFull
                    SinceDiff          = $SinceDiff
                    SinceLog           = $SinceLog
                    DatabaseCreated    = $db.createDate
                    DaysSinceDbCreated = $daysSinceDbCreated
                    Status             = $status
                }
                Select-DefaultView -InputObject $result -Property ComputerName, InstanceName, SqlInstance, Database, LastFullBackup, LastDiffBackup, LastLogBackup
            }
        }
    }
}
