function Test-DbaLogShippingStatus {
    <#
    .SYNOPSIS
    Test-DbaLogShippingStatus returns the status of your log shipping databases

    .DESCRIPTION
    Most of the time your log shipping "just works".
    Checking your log shipping status can be done really easy with this function.

    Make sure you're connecting to the monitoring instance of your log shipping infrastructure.

    The function will return the status for a database. This can be one or more messages in a comma separated list.
    If everything is OK with the database than you should only see the message "All OK".

    .PARAMETER SqlInstance
    SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
    Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
    $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
    To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER Database
    Allows you to filter the results to only return the databases you're interested in. This can be one or more values separated by commas.
    This is not a wildcard and should be the exact database name. See examples for more info.

    .PARAMETER ExcludeDatabase
    Allows you to filter the results to only return the databases you're not interested in. This can be one or more values separated by commas.
    This is not a wildcard and should be the exact database name.

    .PARAMETER Primary
    Allows to filter the results to only return values that apply to the primary instance.

    .PARAMETER Secondary
    Allows to filter the results to only return values that apply to the secondary instance.

    .PARAMETER Simple
    By default all the information will be returned.
    If this parameter is used you get an overview with the SQL Instance, Database, Instance Type and the status

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Original Author: Sander Stad (@sqlstad, sqlstad.nl)
    Tags: LogShipping

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Test-DbaLogShippingStatus

    .EXAMPLE
    Test-DbaLogShippingStatus -SqlInstance sql1

    Retrieves the log ship informaton from sql1 and displays all the information present including the status.

    .EXAMPLE
    Test-DbaLogShippingStatus -SqlInstance sql1 -Database AdventureWorks2014

    Retrieves the log ship information for just the database AdventureWorks.

    .EXAMPLE
    Test-DbaLogShippingStatus -SqlInstance sql1 -Primary

    Retrieves the log ship information and only returns the information for the databases on the primary instance.

    .EXAMPLE
    Test-DbaLogShippingStatus -SqlInstance sql1 -Secondary

    Retrieves the log ship information and only returns the information for the databases on the secondary instance.

    .EXAMPLE
    Test-DbaLogShippingStatus -SqlInstance sql1 -Simple

    Retrieves the log ship information and only returns the columns SQL Instance, Database, Instance Type and Status

#>

    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$Simple,
        [switch]$Primary,
        [switch]$Secondary,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        # Create array list to hold the results
        $collection = New-Object System.Collections.ArrayList

        # Setup the query
        [string[]]$query = "
IF ( OBJECT_ID('tempdb..#logshippingstatus') ) IS NOT NULL
BEGIN
DROP TABLE #logshippingstatus;
END;

CREATE TABLE #logshippingstatus
(
    Status BIT ,
    IsPrimary BIT ,
    Server VARCHAR(100) ,
    DatabaseName VARCHAR(100) ,
    TimeSinceLastBackup INT ,
    LastBackupFile VARCHAR(255) ,
    BackupThresshold INT ,
    IsBackupAlertEnabled BIT ,
    TimeSinceLastCopy INT ,
    LastCopiedFile VARCHAR(255) ,
    TimeSinceLastRestore INT ,
    LastRestoredFile VARCHAR(255) ,
    LastRestoredLatency INT ,
    RestoreThresshold INT ,
    IsRestoreAlertEnabled BIT
);

INSERT INTO #logshippingstatus
(   Status ,
    IsPrimary ,
    Server ,
    DatabaseName ,
    TimeSinceLastBackup ,
    LastBackupFile ,
    BackupThresshold ,
    IsBackupAlertEnabled ,
    TimeSinceLastCopy ,
    LastCopiedFile ,
    TimeSinceLastRestore ,
    LastRestoredFile ,
    LastRestoredLatency ,
    RestoreThresshold ,
    IsRestoreAlertEnabled
)
EXEC master.sys.sp_help_log_shipping_monitor"

        $select = "SELECT * FROM #logshippingstatus"

        if ($Database -or $ExcludeDatabase) {

            if ($database) {
                $where += "DatabaseName IN ('$($Database -join ',')')"
            }
            elseif ($ExcludeDatabase) {
                $where += "DatabaseName NOTIN ('$($ExcludeDatabase -join ',')')"
            }

            $select = "$select WHERE $where"
        }

        $query += $select
        $query += "DROP TABLE #logshippingstatus"
        $sql = $query -join ";`n"
        Write-Message -level Debug -Message $sql
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

            # Check the variables
            if ($Primary -and $Secondary) {
                Stop-Function -Message "Invalid parameter combination. Please enter either -Primary or -Secondary" -Target $instance -Continue
            }

            # Get the log shipped databases
            $results = $server.Query($sql)

            # Check if any rows were returned
            if ($results.Count -lt 1) {
                Stop-Function -Message "No information available about any log shipped databases for $instance. Please check the instance name." -Target $instance -Continue
            }

            # Filter the results
            if ($Primary) {
                $results = $results | Where-Object { $_.IsPrimary -eq $true }
            }

            if ($Secondary) {
                $results = $results | Where-Object { $_.IsPrimary -eq $false }
            }

            # Loop through each of the results
            foreach ($result in $results) {

                # Setup a variable to hold the errors
                $statusDetails = @()

                # Check the status of the row is true whih indicates that something is wrong
                if ($result.Status) {
                    # Check if the row is part of the primary or secondary instance
                    if ($result.IsPrimary) {
                        # Check the backup
                        if (-not $result.TimeSinceLastBackup) {
                            $statusDetails += "The backup has never been executed."
                        }
                        elseif ($result.TimeSinceLastBackup -ge $result.BackupThresshold) {
                            $statusDetails += "The backup has not been executed in the last $($result.BackupThresshold) minutes"
                        }
                    }
                    elseif (-not $result.IsPrimary) {
                        # Check the restore
                        if ($result.TimeSinceLastRestore -eq $null) {
                            $statusDetails += "The restore has never been executed."
                        }
                        elseif ($result.TimeSinceLastRestore -ge $result.RestoreThresshold) {
                            $statusDetails += "The restore has not been executed in the last $($result.RestoreThresshold) minutes"
                        }
                    }
                }
                else {
                    $statusDetails += "All OK"
                }


                # Check the time for the backup, copy and restore
                if ($result.TimeSinceLastBackup -eq [DBNull]::Value) {
                    $lastBackup = "N/A"
                }
                else {
                    $lastBackup = (Get-Date).AddMinutes( - $result.TimeSinceLastBackup)
                }

                if ($result.TimeSinceLastCopy -eq [DBNull]::Value) {
                    $lastCopy = "N/A"
                }
                else {
                    $lastCopy = (Get-Date).AddMinutes( - $result.TimeSinceLastCopy)
                }

                if ($result.TimeSinceLastRestore -eq [DBNull]::Value) {
                    $lastRestore = "N/A"
                }
                else {
                    $lastRestore = (Get-Date).AddMinutes( - $result.TimeSinceLastRestore)
                }

                # Set up the custom object
                $null = $collection.Add([PSCustomObject]@{
                        ComputerName          = $server.NetName
                        InstanceName          = $server.ServiceName
                        SqlInstance           = $server.DomainInstanceName
                        Database              = $result.DatabaseName
                        InstanceType          = switch ($result.IsPrimary) { $true { "Primary Instance" } $false { "Secondary Instance" } }
                        TimeSinceLastBackup   = $lastBackup
                        LastBackupFile        = $result.LastBackupFile
                        BackupThresshold      = $result.BackupThresshold
                        IsBackupAlertEnabled  = $result.IsBackupAlertEnabled
                        TimeSinceLastCopy     = $lastCopy
                        LastCopiedFile        = $result.LastCopiedFile
                        TimeSinceLastRestore  = $lastRestore
                        LastRestoredFile      = $result.LastRestoredFile
                        LastRestoredLatency   = $result.LastRestoredLatency
                        RestoreThresshold     = $result.RestoreThresshold
                        IsRestoreAlertEnabled = $result.IsRestoreAlertEnabled
                        Status                = $statusDetails -join ","
                    })

            }

            if ($Simple) {
                return $collection | Select-Object SqlInstance, Database, InstanceType, Status
            }
            else {
                return $collection
            }
        }
    }
}