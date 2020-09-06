function Get-DbaDbLogShipError {
    <#
    .SYNOPSIS
        Get-DbaDbLogShipError returns all the log shipping errors that occurred

    .DESCRIPTION
        When your log shipping fails it's sometimes hard to see why is fails.
        Using this function you'll be able to find out what went wrong in a short amount of time.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Allows you to filter the results to only return the databases you're interested in. This can be one or more values separated by commas.
        This is not a wildcard and should be the exact database name. See examples for more info.

    .PARAMETER ExcludeDatabase
        Allows you to filter the results to only return the databases you're not interested in. This can be one or more values separated by commas.
        This is not a wildcard and should be the exact database name.

    .PARAMETER Action
        Filter to get the log shipping action that has occurred like Backup, Copy, Restore.
        By default all the actions are returned.

    .PARAMETER DateTimeFrom
        Filter the results based on the date starting from datetime X

    .PARAMETER DateTimeTo
        Filter the results based on the date ending with datetime X

    .PARAMETER Primary
        Allows to filter the results to only return values that apply to the primary instance.

    .PARAMETER Secondary
        Allows to filter the results to only return values that apply to the secondary instance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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