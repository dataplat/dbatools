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

        This script will only display the newest timestamp. If -Verbose is specified, the function will announce every time more than one dbi_dbccLastKnownGood fields is encountered.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more database(s) to exclude from processing.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CHECKDB, Database
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
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
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

                $daysSinceCheckDb = (New-TimeSpan -Start $lastKnownGood -End (Get-Date)).Days
                $daysSinceDbCreated = (New-TimeSpan -Start $db.createDate -End (Get-Date)).TotalDays

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