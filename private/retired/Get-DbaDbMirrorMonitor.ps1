function Get-DbaDbMirrorMonitor {
    <#
    .SYNOPSIS
        Retrieves database mirroring performance metrics and monitoring history from SQL Server instances

    .DESCRIPTION
        Retrieves detailed database mirroring performance statistics from the msdb monitoring tables, helping you track mirroring health and identify performance bottlenecks. This function executes sp_dbmmonitorresults to pull metrics like log generation rates, send rates, transaction delays, and recovery progress from both principal and mirror databases.

        Use this when troubleshooting mirroring performance issues, monitoring replication lag, or generating compliance reports for high availability configurations. You can optionally refresh the monitoring data before retrieval and filter results by time periods or row counts to focus on specific timeframes.

        The function returns comprehensive metrics including unsent log size, recovery rates, average delays, and witness status - all the key indicators DBAs need to assess mirroring health without manually querying system tables.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which mirrored databases to monitor. Only databases configured for mirroring will return results.
        Use this to focus monitoring on specific databases instead of checking all mirrored databases on the instance.

    .PARAMETER Update
        Forces a refresh of mirroring statistics before retrieving results by calling sp_dbmmonitorupdate.
        Use this when you need the most current metrics, though SQL Server automatically limits updates to once every 15 seconds and requires sysadmin privileges.

    .PARAMETER LimitResults
        Controls how much historical monitoring data to retrieve from the msdb.dbo.dbm_monitor_data table.
        Choose shorter time periods for recent performance analysis or longer periods for trend analysis. Row-based options return the most recent entries regardless of time.

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
        Accepts database objects from Get-DbaDatabase pipeline input.
        Use this when you want to filter databases first before checking their mirroring status.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per monitoring record retrieved from the database mirroring monitor table. Multiple records may be returned depending on the -LimitResults parameter value.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - DatabaseName: Name of the mirrored database
        - Role: The role of the server instance - Principal or Mirror
        - MirroringState: Current mirroring state (Synchronizing, Synchronized, Suspended, Disconnected, etc.)
        - WitnessStatus: Status of the witness server (Connected, Disconnected, Quorum Lost, etc.)
        - LogGenerationRate: Rate at which transaction log is being generated on the principal (KB/sec)
        - UnsentLog: Amount of log not yet sent to the mirror (KB)
        - SendRate: Rate at which log is being sent to the mirror (KB/sec)
        - UnrestoredLog: Amount of log not yet restored on the mirror (KB)
        - RecoveryRate: Rate at which log is being restored on the mirror (KB/sec)
        - TransactionDelay: Delay caused by database mirroring for committed transactions (milliseconds)
        - TransactionsPerSecond: Number of transactions per second being processed
        - AverageDelay: Average transaction delay (milliseconds)
        - TimeRecorded: DateTime when this monitoring record was recorded
        - TimeBehind: Amount the mirror lags behind the principal (milliseconds)
        - LocalTime: Local time on the server when the record was generated

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
                $sql = "EXEC msdb.dbo.sp_dbmmonitorresults @database_name = '$db', @mode = $rows, @update_table = $updatebool"
                $results = $db.Parent.Query($sql)

                foreach ($result in $results) {
                    [PSCustomObject]@{
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