function Get-DbaLogShippingError {
    <#
    .SYNOPSIS
    Get-DbaLogShippingError returns all the log shipping errors that occured

    .DESCRIPTION
    When your log shipping fails it's sometimes hard to see why is fails.
    Using this function you'll be able to find out what went wrong in a short amount of time.

    .PARAMETER SqlInstance
    SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
    Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Database
    Allows you to filter the results to only return the databases you're interested in. This can be one or more values separated by commas.
    This is not a wildcard and should be the exact database name. See examples for more info.

    .PARAMETER ExcludeDatabase
    Allows you to filter the results to only return the databases you're not interested in. This can be one or more values separated by commas.
    This is not a wildcard and should be the exact database name.

    .PARAMETER Action
    Filter to get the log shipping action that has occured like Backup, Copy, Restore.
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
    Original Author: Sander Stad (@sqlstad, sqlstad.nl)
    Tags: LogShipping

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Get-DbaLogShippingError

    .EXAMPLE
    Get-DbaLogShippingError -SqlInstance sql1

    Get all the log shipping errors that occured

    .EXAMPLE
    Get-DbaLogShippingError -SqlInstance sql1 -Action Backup

    Get the errors that have something to do with the backup of the databases

    .EXAMPLE
    Get-DbaLogShippingError -SqlInstance sql1 -Secondary

    Get the errors that occured on the secondary instance.
    This will return the copy of the restore actions because those only occur on the secondary instance

    .EXAMPLE
    Get-DbaLogShippingError -SqlInstance sql1 -DateTimeFrom "01/05/2018"

    Get the errors that have occured from "01/05/2018". This can also be of format "yyyy-MM-dd"

    .EXAMPLE
    Get-DbaLogShippingError -SqlInstance sql1 -Secondary -DateTimeFrom "01/05/2018" -DateTimeTo "2018-01-07"

    Get the errors that have occured between "01/05/2018" and "01/07/2018".
    See that is doesn't matter how the date is represented.

#>

    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
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
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {

        # Create array list to hold the results
        $collection = New-Object System.Collections.ArrayList

    }

    process {
        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
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
                    $results = $results | Where-Object {$_.Logtime -ge $DateTimeFrom}
                }

                if ($DateTimeTo) {
                    $results = $results | Where-Object {$_.Logtime -le $DateTimeTo}
                }

                if ($Primary) {
                    $results = $results | Where-Object {$_.Instance -eq 'Primary'}
                }

                if ($Secondary) {
                    $results = $results | Where-Object {$_.Instance -eq 'Secondary'}
                }

                # Loop through each of the results
                foreach ($result in $results) {
                    # Set up the custom object
                    $null = $collection.Add([PSCustomObject]@{
                            ComputerName   = $server.NetName
                            InstanceName   = $server.ServiceName
                            SqlInstance    = $server.DomainInstanceName
                            Database       = $result.DatabaseName
                            Instance       = $result.Instance
                            Action         = $result.Action
                            SessionID      = $result.SessionID
                            SequenceNumber = $result.SequenceNumber
                            LogTime        = $result.LogTime
                            Message        = $result.Message
                        })

                } # for each result
            }
            else {
                Write-Message -Message "No log shipping errors found" -Level Verbose
            }

        } # foreach instance

        return $collection

    } # end process

}

