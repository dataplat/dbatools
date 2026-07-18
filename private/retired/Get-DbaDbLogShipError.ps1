function Get-DbaDbLogShipError {
    <#
    .SYNOPSIS
        Retrieves log shipping error details from msdb to troubleshoot failed backup, copy, and restore operations

    .DESCRIPTION
        Queries the log shipping monitor error detail table in msdb to return comprehensive error information when log shipping operations fail.
        Identifies which specific action failed (backup on primary, copy, or restore on secondary) along with session details and error messages.
        Saves time by consolidating error details from both primary and secondary instances into a single view, so you don't have to manually query multiple system tables.
        Essential for troubleshooting log shipping failures and determining whether issues occurred during backup, file copy, or database restore phases.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to include when retrieving log shipping errors. Requires exact database names, not wildcards.
        Use this when troubleshooting specific databases rather than reviewing all log shipped databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the log shipping error results. Requires exact database names, not wildcards.
        Useful when you want to see errors for all databases except certain ones, like excluding test databases from production error reviews.

    .PARAMETER Action
        Filters errors by log shipping operation type: Backup (primary), Copy (between servers), or Restore (secondary).
        Use this to isolate which phase of log shipping is failing when troubleshooting multi-step log shipping workflows.

    .PARAMETER DateTimeFrom
        Sets the earliest date and time for error records to include in results.
        Essential for focusing on recent failures or analyzing errors that occurred after a specific event or change.

    .PARAMETER DateTimeTo
        Sets the latest date and time for error records to include in results.
        Combined with DateTimeFrom, this creates a specific time window for analyzing log shipping failures during maintenance windows or incidents.

    .PARAMETER Primary
        Returns only errors from backup operations that occur on the primary server.
        Use this when troubleshooting backup failures or primary-side log shipping issues like insufficient disk space or backup device problems.

    .PARAMETER Secondary
        Returns only errors from copy and restore operations that occur on secondary servers.
        Use this when troubleshooting file transfer failures or restore issues on the destination server, such as network connectivity or disk space problems.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per log shipping error found. If no errors exist, nothing is returned.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: Name of the database involved in the log shipping error
        - Instance: The role where the error occurred - either "Primary" (backup operation) or "Secondary" (copy or restore operation)
        - Action: The type of log shipping operation that failed - "Backup" (primary server), "Copy" (between servers), or "Restore" (secondary server)
        - SessionID: Unique identifier for the log shipping session in which the error occurred
        - SequenceNumber: Sequential number of this error within the session for ordering multiple errors
        - LogTime: DateTime when the error was recorded in the log shipping monitor tables
        - Message: The detailed error message describing what went wrong (e.g., file not found, insufficient disk space, network timeout)

    .NOTES
        Tags: LogShipping
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbLogShipError

    .EXAMPLE
        PS C:\> Get-DbaDbLogShipError -SqlInstance sql1

        Get all the log shipping errors that occurred

    .EXAMPLE
        PS C:\> Get-DbaDbLogShipError -SqlInstance sql1 -Action Backup

        Get the errors that have something to do with the backup of the databases

    .EXAMPLE
        PS C:\> Get-DbaDbLogShipError -SqlInstance sql1 -Secondary

        Get the errors that occurred on the secondary instance.
        This will return the copy of the restore actions because those only occur on the secondary instance

    .EXAMPLE
        PS C:\> Get-DbaDbLogShipError -SqlInstance sql1 -DateTimeFrom "01/05/2018"

        Get the errors that have occurred from "01/05/2018". This can also be of format "yyyy-MM-dd"

    .EXAMPLE
        PS C:\> Get-DbaDbLogShipError -SqlInstance sql1 -Secondary -DateTimeFrom "01/05/2018" -DateTimeTo "2018-01-07"

        Get the errors that have occurred between "01/05/2018" and "01/07/2018".
        See that is doesn't matter how the date is represented.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [ValidateSet("Backup", "Copy", "Restore")]
        [string[]]$Action,
        [datetime]$DateTimeFrom,
        [datetime]$DateTimeTo,
        [switch]$Primary,
        [switch]$Secondary,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.EngineEdition -match "Express") {
                Write-Message -Level Warning -Message "$instance is Express Edition which does not support Log Shipping"
                continue
            }

            $query = "
CREATE TABLE #DatabaseID
(
    DatabaseName VARCHAR(128),
    DatabaseID UNIQUEIDENTIFIER,
    Instance VARCHAR(20)
);

INSERT INTO #DatabaseID
(
    DatabaseName,
    DatabaseID,
    Instance
)
SELECT secondary_database,
        secondary_id,
        'Secondary'
FROM msdb.dbo.log_shipping_secondary_databases;


INSERT INTO #DatabaseID
(
    DatabaseName,
    DatabaseID,
    Instance
)
SELECT primary_database,
        primary_id,
        'Primary'
FROM msdb.dbo.log_shipping_primary_databases;


SELECT di.DatabaseName,
        di.Instance,
        CASE lsmed.[agent_type]
            WHEN 0 THEN
                'Backup'
            WHEN 1 THEN
                'Copy'
            WHEN 2 THEN
                'Restore'
            ELSE
                ''
        END AS [Action],
        lsmed.[session_id] AS SessionID,
        lsmed.[sequence_number] AS SequenceNumber,
        lsmed.[log_time] AS LogTime,
        lsmed.[message] AS [Message]
FROM msdb.dbo.log_shipping_monitor_error_detail AS lsmed
    INNER JOIN #DatabaseID AS di
        ON di.DatabaseID = lsmed.agent_id
ORDER BY lsmed.[log_time],
            lsmed.[database_name],
            lsmed.[agent_type],
            lsmed.[session_id],
            lsmed.[sequence_number];

DROP TABLE #DatabaseID;"

            # Get the log shipping errors
            $results = $server.Query($query)

            if ($results.Count -ge 1) {

                # Filter the results
                if ($Database) {
                    $results = $results | Where-Object { $_.DatabaseName -in $Database }
                }

                if ($Action) {
                    $results = $results | Where-Object { $_.Action -in $Action }
                }

                if ($DateTimeFrom) {
                    $results = $results | Where-Object { $_.Logtime -ge $DateTimeFrom }
                }

                if ($DateTimeTo) {
                    $results = $results | Where-Object { $_.Logtime -le $DateTimeTo }
                }

                if ($Primary) {
                    $results = $results | Where-Object { $_.Instance -eq 'Primary' }
                }

                if ($Secondary) {
                    $results = $results | Where-Object { $_.Instance -eq 'Secondary' }
                }

                foreach ($result in $results) {
                    [PSCustomObject]@{
                        ComputerName   = $server.ComputerName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        Database       = $result.DatabaseName
                        Instance       = $result.Instance
                        Action         = $result.Action
                        SessionID      = $result.SessionID
                        SequenceNumber = $result.SequenceNumber
                        LogTime        = $result.LogTime
                        Message        = $result.Message
                    }

                }
            } else {
                Write-Message -Message "No log shipping errors found" -Level Verbose
            }
        }
    }
}