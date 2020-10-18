function Get-DbaDbMirrorMonitor {
    <#
    .SYNOPSIS
        Returns status rows for a monitored database from the status table in which database mirroring monitoring history is stored and allows you to choose whether the procedure obtains the latest status beforehand.

    .DESCRIPTION
        Returns status rows for a monitored database from the status table in which database mirroring monitoring history is stored and allows you to choose whether the procedure obtains the latest status beforehand.

        Basically executes sp_dbmmonitorresults.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database.

    .PARAMETER Database
        The target database.

    .PARAMETER Update
        Updates the status for the database by calling sp_dbmmonitorupdate before computing the results.
        However, if the status table has been updated within the previous 15 seconds, or the user is not a member of the sysadmin fixed server role, the command runs without updating the status.

    .PARAMETER LimitResults
        Limit results. Defaults to last two hours.

        Options include:
        LastRow
        LastTwoHours
        LastFourHours
        LastEightHours
        LastDay
        LastTwoDays
        Last100Rows
        Last500Rows
        Last1000Rows
        Last1000000Rows

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Mirroring, Mirror, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMirrorMonitor

    .EXAMPLE
        PS C:\> Get-DbaDbMirrorMonitor -SqlInstance sql2008, sql2012

        Returns last two hours' worth of status rows for a monitored database from the status table on sql2008 and sql2012.

    .EXAMPLE
        PS C:\> Get-DbaDbMirrorMonitor -SqlInstance sql2005 -LimitResults LastDay -Update

        Updates monitor stats then returns the last 24 hours worth of status rows for a monitored database from the status table on sql2008 and sql2012.
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Update,
        [ValidateSet('LastRow', 'LastTwoHours', 'LastFourHours', 'LastEightHours', 'LastDay', 'LastTwoDays', 'Last100Rows', 'Last500Rows', 'Last1000Rows', 'Last1000000Rows')]
        [string]$LimitResults = 'LastTwoHours',
        [switch]$EnableException
    )
    begin {
        $rows = switch ($LimitResults) {
            'LastRow' { 0 }
            'LastTwoHours' { 1 }
            'LastFourHours' { 2 }
            'LastEightHours' { 3 }
            'LastDay' { 4 }
            'LastTwoDays' { 5 }
            'Last100Rows' { 6 }
            'Last500Rows' { 7 }
            'Last1000000Rows' { 8 }
        }
        $updatebool = switch ($Update) {
            $false { 0 }
            $true { 1 }
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if (-not ($db.Parent.Databases['msdb'].Tables['dbm_monitor_data'].Name)) {
                Stop-Function -Continue -Message "msdb.dbo.dbm_monitor_data not found. Please run Add-DbaDbMirrorMonitor then you can get monitor stats."
            }
            try {
                $sql = "msdb.dbo.sp_dbmmonitorresults $db, $rows, $updatebool"
                $results = $db.Parent.Query($sql)

                foreach ($result in $results) {
                    [pscustomobject]@{
                        ComputerName          = $db.Parent.ComputerName
                        InstanceName          = $db.Parent.ServiceName
                        SqlInstance           = $db.Parent.DomainInstanceName
                        DatabaseName          = $result.database_name
                        Role                  = $result.role
                        MirroringState        = $result.mirroring_state
                        WitnessStatus         = $result.witness_status
                        LogGenerationRate     = $result.log_generation_rate
                        UnsentLog             = $result.unsent_log
                        SendRate              = $result.send_rate
                        UnrestoredLog         = $result.unrestored_log
                        RecoveryRate          = $result.recovery_rate
                        TransactionDelay      = $result.transaction_delay
                        TransactionsPerSecond = $result.transactions_per_sec
                        AverageDelay          = $result.average_delay
                        TimeRecorded          = $result.time_recorded
                        TimeBehind            = $result.time_behind
                        LocalTime             = $result.local_time
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}