function Get-DbaLastGoodCheckDb {
    <#
    .SYNOPSIS
        Retrieves the last successful DBCC CHECKDB timestamp and integrity status for databases

    .DESCRIPTION
        Retrieves and compares the timestamp for the last successful DBCC CHECKDB operation along with database creation dates. This helps DBAs monitor database integrity checking compliance and identify databases that need attention.

        The function returns comprehensive information including days since the last good CHECKDB, database creation date, current status assessment (Ok, New database not checked yet, or CheckDB should be performed), and data purity settings. Use this to quickly identify which databases are overdue for integrity checks in your maintenance routines.

        This function supports SQL Server 2005 and higher. For SQL Server 2008 and earlier, it uses DBCC DBINFO() WITH TABLERESULTS to extract the dbi_dbccLastKnownGood field. For newer versions, it uses the LastGoodCheckDbTime property from SMO.

        Please note that this script uses the DBCC DBINFO() WITH TABLERESULTS. DBCC DBINFO has several known weak points, such as:
        - DBCC DBINFO is an undocumented feature/command.
        - The LastKnowGood timestamp is updated when a DBCC CHECKFILEGROUP is performed.
        - The LastKnowGood timestamp is updated when a DBCC CHECKDB WITH PHYSICAL_ONLY is performed.
        - The LastKnowGood timestamp does not get updated when a database in READ_ONLY.

        An empty ($null) LastGoodCheckDb result indicates that a good DBCC CHECKDB has never been performed.

        SQL Server 2008R2 has a "bug" that causes each databases to possess two dbi_dbccLastKnownGood fields, instead of the normal one.

        This script will only display the newest timestamp. If -Verbose is specified, the function will announce every time more than one dbi_dbccLastKnownGood fields is encountered.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to check for their last good CHECKDB status. Accepts wildcards for pattern matching.
        When omitted, all user and system databases on the instance will be processed. Use this to focus on specific databases or groups of databases when monitoring CHECKDB compliance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the CHECKDB status check. Commonly used to skip system databases like TempDB or databases with known maintenance schedules.
        Accepts wildcards and multiple database names to filter out databases that don't need regular CHECKDB monitoring.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase, allowing for complex filtering scenarios before checking CHECKDB status.
        Use this when you need to apply advanced database filtering logic or when chaining multiple dbatools commands together.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CHECKDB, Database, Utility
        Author: Jakob Bindslet (jakob@bindslet.dk)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Ref:
        DBCC CHECKDB:
        https://msdn.microsoft.com/en-us/library/ms176064.aspx
        http://www.sqlcopilot.com/dbcc-checkdb.html
        Data Purity:
        http://www.sqlskills.com/blogs/paul/checkdb-from-every-angle-how-to-tell-if-data-purity-checks-will-be-run/
        https://www.mssqltips.com/sqlservertip/1988/ensure-sql-server-data-purity-checks-are-performed/

    .LINK
        https://dbatools.io/Get-DbaLastGoodCheckDb

    .OUTPUTS
        PSCustomObject

        Returns one object per database processed, containing database integrity check status and compliance metrics.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database
        - DatabaseCreated: DateTime when the database was created; $null if the date cannot be determined
        - LastGoodCheckDb: DateTime of the last successful DBCC CHECKDB operation; $null if CHECKDB has never been performed
        - DaysSinceDbCreated: Numeric value (days and fractional days) representing time elapsed since database creation
        - DaysSinceLastGoodCheckDb: Integer number of days since the last successful CHECKDB; only present if CHECKDB was previously run
        - Status: String status indicator - "Ok" (CHECKDB within last 7 days), "New database, not checked yet" (created within last 7 days), or "CheckDB should be performed" (overdue for CHECKDB)
        - DataPurityEnabled: Boolean indicating if data purity checks are enabled; $null for SQL Server 2008 and newer when not running as sysadmin; based on dbi_dbccFlags field for SQL Server 2005-2008
        - CreateVersion: Integer representing the internal version of the database (from dbi_createVersion DBCC DBINFO field); available only when running SQL Server 2008 and earlier or as sysadmin
        - DbccFlags: Integer representing DBCC flags from the database (from dbi_dbccFlags DBCC DBINFO field); available only when running SQL Server 2008 and earlier or as sysadmin

        Notes:
        - For SQL Server 2005-2008: Uses DBCC DBINFO() WITH TABLERESULTS to retrieve LastGoodCheckDb, CreateVersion, and DbccFlags
        - For SQL Server 2008 R2 and newer: Uses SMO LastGoodCheckDbTime property (CreateVersion and DbccFlags are not available)
        - CreateVersion and DbccFlags are only populated when running as sysadmin or on SQL Server versions prior to 2010
        - If CHECKDB has never been performed, LastGoodCheckDb will be $null and Status will indicate "New database" or "should be performed"

    .EXAMPLE
        PS C:\> Get-DbaLastGoodCheckDb -SqlInstance ServerA\sql987

        Returns a custom object displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled

    .EXAMPLE
        PS C:\> Get-DbaLastGoodCheckDb -SqlInstance ServerA\sql987 -SqlCredential sqladmin | Format-Table -AutoSize

        Returns a formatted table displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled. Authenticates using SQL Server authentication.

    .EXAMPLE
        PS C:\> Get-DbaLastGoodCheckDb -SqlInstance sql2016 -ExcludeDatabase "TempDB" | Format-Table -AutoSize

        Returns a formatted table displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled. All databases except for "TempDB" will be displayed in the output.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database DB1, DB2 | Get-DbaLastGoodCheckDb | Format-Table -AutoSize

        Returns a formatted table displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled. Only databases DB1 abd DB2 will be displayed in the output.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -not 'SqlInstance', 'InputObject') {
            Write-Message -Level Warning -Message "You must specify either a SQL instance or supply an InputObject"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $databases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $databases = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $databases = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server or database."
                    return
                }
            }

            foreach ($db in $databases) {
                $server = $db.Parent
                Write-Message -Level Verbose -Message "Processing $($db.Name) on $($server.Name)."

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $($db.Name) is not accessible. Skipping database." -Continue -Target $db
                }

                $isAzure = $db.Parent.DatabaseEngineType -match "Azure"

                if (-not $isAzure) {
                    $isAdmin = $db.Parent.ConnectionContext.ExecuteScalar("SELECT IS_SRVROLEMEMBER('sysadmin')")
                } else {
                    $isAdmin = $false
                }

                if ($db.Parent.VersionMajor -lt 10 -or $isAdmin) {
                    $dbNameQuoted = '[' + $db.Name.Replace(']', ']]') + ']'
                    $sql = "DBCC DBINFO ($dbNameQuoted) WITH TABLERESULTS"
                    Write-Message -Level Debug -Message "T-SQL: $sql"

                    $resultTable = $db.ExecuteWithResults($sql).Tables[0]
                    [datetime[]]$lastKnownGoodArray = $resultTable | Where-Object Field -eq 'dbi_dbccLastKnownGood' | Select-Object -ExpandProperty Value

                    ## look for databases with two or more occurrences of the field dbi_dbccLastKnownGood
                    if ($lastKnownGoodArray.count -ge 2) {
                        Write-Message -Level Verbose -Message "The database $db has $($lastKnownGoodArray.count) dbi_dbccLastKnownGood fields. This script will only use the newest."
                    }
                    [datetime]$lastKnownGood = $lastKnownGoodArray | Sort-Object -Descending | Select-Object -First 1

                    [int]$createVersion = ($resultTable | Where-Object Field -eq 'dbi_createVersion').Value
                    [int]$dbccFlags = ($resultTable | Where-Object Field -eq 'dbi_dbccFlags').Value

                    if (($createVersion -lt 611) -and ($dbccFlags -eq 0)) {
                        $dataPurityEnabled = $false
                    } else {
                        $dataPurityEnabled = $true
                    }
                } else {
                    $lastKnownGood = $db.LastGoodCheckDbTime
                    $dataPurityEnabled = $null
                }

                if ($lastKnownGood -isnot [datetime]) {
                    $lastKnownGood = Get-Date '1/1/1900 12:00:00 AM'
                }

                $datecreated = $db.createDate
                if ($datecreated -isnot [datetime]) {
                    $datecreated = Get-Date '1/1/1900 12:00:00 AM'
                }

                $daysSinceCheckDb = (New-TimeSpan -Start $lastKnownGood -End (Get-Date)).Days
                $daysSinceDbCreated = (New-TimeSpan -Start $datecreated -End (Get-Date)).TotalDays

                if ($daysSinceCheckDb -lt 7) {
                    $Status = 'Ok'
                } elseif ($daysSinceDbCreated -lt 7) {
                    $Status = 'New database, not checked yet'
                } else {
                    $Status = 'CheckDB should be performed'
                }

                if ($lastKnownGood -eq '1/1/1900 12:00:00 AM') {
                    Remove-Variable -Name lastKnownGood, daysSinceCheckDb
                }

                if ($datecreated -eq '1/1/1900 12:00:00 AM') {
                    Remove-Variable -Name datecreated
                }


                [PSCustomObject]@{
                    ComputerName             = $server.ComputerName
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