function Get-DbaLastGoodCheckDb {
    <#
        .SYNOPSIS
            Get date/time for last known good DBCC CHECKDB

        .DESCRIPTION
            Retrieves and compares the date/time for the last known good DBCC CHECKDB, as well as the creation date/time for the database.

            This function supports SQL Server 2005 and higher.

            Please note that this script uses the DBCC DBINFO() WITH TABLERESULTS. DBCC DBINFO has several known weak points, such as:
            - DBCC DBINFO is an undocumented feature/command.
            - The LastKnowGood timestamp is updated when a DBCC CHECKFILEGROUP is performed.
            - The LastKnowGood timestamp is updated when a DBCC CHECKDB WITH PHYSICAL_ONLY is performed.
            - The LastKnowGood timestamp does not get updated when a database in READ_ONLY.

            An empty ($null) LastGoodCheckDb result indicates that a good DBCC CHECKDB has never been performed.

            SQL Server 2008R2 has a "bug" that causes each databases to possess two dbi_dbccLastKnownGood fields, instead of the normal one.

            This script will only display this function to only display the newest timestamp. If -Verbose is specified, the function will announce every time more than one dbi_dbccLastKnownGood fields is encountered.

        .PARAMETER SqlInstance
            The SQL Server instance to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies one or more database(s) to process. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies one or more database(s) to exclude from processing.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: CHECKDB, Database
            Author: Jakob Bindslet (jakob@bindslet.dk)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            DBCC CHECKDB:
                https://msdn.microsoft.com/en-us/library/ms176064.aspx
                http://www.sqlcopilot.com/dbcc-checkdb.html
            Data Purity:
                http://www.sqlskills.com/blogs/paul/checkdb-from-every-angle-how-to-tell-if-data-purity-checks-will-be-run/
                https://www.mssqltips.com/sqlservertip/1988/ensure-sql-server-data-purity-checks-are-performed/

        .EXAMPLE
            Get-DbaLastGoodCheckDb -SqlInstance ServerA\sql987

            Returns a custom object displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled

        .EXAMPLE
            Get-DbaLastGoodCheckDb -SqlInstance ServerA\sql987 -SqlCredential (Get-Credential sqladmin) | Format-Table -AutoSize

            Returns a formatted table displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled. Authenticates using SQL Server authentication.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias('Silent')]
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.versionMajor -lt 9) {
                Stop-Function -Message "Get-DbaLastGoodCheckDb is only supported on SQL Server 2005 and above. Skipping Instance." -Continue -Target $instance
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instances."

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible. Skipping database." -Continue -Target $db
                }

                $sql = "DBCC DBINFO ([$($db.name)]) WITH TABLERESULTS"
                Write-Message -Level Debug -Message "T-SQL: $sql"

                $resultTable = $db.ExecuteWithResults($sql).Tables[0]
                [datetime[]]$lastKnownGoodArray = $resultTable | Where-Object Field -eq 'dbi_dbccLastKnownGood' | Select-Object -ExpandProperty Value

                ## look for databases with two or more occurrences of the field dbi_dbccLastKnownGood
                if ($lastKnownGoodArray.count -ge 2) {
                    Write-Message -Level Verbose -Message "The database $db has $($lastKnownGoodArray.count) dbi_dbccLastKnownGood fields. This script will only use the newest!"
                }
                [datetime]$lastKnownGood = $lastKnownGoodArray | Sort-Object -Descending | Select-Object -First 1

                [int]$createVersion = ($resultTable | Where-Object Field -eq 'dbi_createVersion').Value
                [int]$dbccFlags = ($resultTable | Where-Object Field -eq 'dbi_dbccFlags').Value

                if (($createVersion -lt 611) -and ($dbccFlags -eq 0)) {
                    $dataPurityEnabled = $false
                }
                else {
                    $dataPurityEnabled = $true
                }

                $daysSinceCheckDb = (New-TimeSpan -Start $lastKnownGood -End (Get-Date)).Days
                $daysSinceDbCreated = (New-TimeSpan -Start $db.createDate -End (Get-Date)).TotalDays

                if ($daysSinceCheckDb -lt 7) {
                    $Status = 'Ok'
                }
                elseif ($daysSinceDbCreated -lt 7) {
                    $Status = 'New database, not checked yet'
                }
                else {
                    $Status = 'CheckDB should be performed'
                }

                if ($lastKnownGood -eq '1/1/1900 12:00:00 AM') {
                    Remove-Variable -Name lastKnownGood, daysSinceCheckDb
                }

                [PSCustomObject]@{
                    ComputerName             = $server.NetName
                    InstanceName             = $server.ServiceName
                    SqlInstance              = $server.DomainInstanceName
                    Database                 = $db.name
                    DatabaseCreated          = $db.createDate
                    LastGoodCheckDb          = $lastKnownGood
                    DaysSinceDbCreated       = $daysSinceDbCreated
                    DaysSinceLastGoodCheckDb = $daysSinceCheckDb
                    Status                   = $status
                    DataPurityEnabled        = $dataPurityEnabled
                    CreateVersion            = $createVersion
                    DbccFlags                = $dbccFlags
                }
            }
        }
    }
}
