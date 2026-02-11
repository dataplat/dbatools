function Find-DbaSimilarTable {
    <#
    .SYNOPSIS
        Finds tables and views with similar structures by comparing column names across databases

    .DESCRIPTION
        Analyzes table and view structures across databases by comparing column names using INFORMATION_SCHEMA views. Returns a match percentage showing how similar structures are based on shared column names.

        Perfect for finding archive tables that mirror production structures, identifying tables that might serve similar purposes across databases, or discovering where specific table patterns are used throughout your SQL Server environment.

        You can search across all databases or target specific databases, schemas, or tables. The function calculates match percentages so you can set minimum thresholds to filter results and focus on the most relevant matches.

        More information can be found here: https://sqljana.wordpress.com/2017/03/31/sql-server-find-tables-with-similar-table-structure/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for similar table structures. Accepts multiple database names.
        Use this to limit the search scope when you know which databases contain the tables you're comparing.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the similarity search. Accepts multiple database names.
        Useful for skipping temp databases, development copies, or databases with known irrelevant structures.

    .PARAMETER SchemaName
        Limits the search to tables within a specific schema. Only tables in this schema will be used as reference structures.
        Use this when comparing tables within a logical grouping like 'Sales', 'HR', or 'Archive' schemas.

    .PARAMETER TableName
        Uses a specific table as the reference structure to find similar tables across databases.
        Perfect for finding archive versions of production tables or identifying tables that mirror a known structure.
        When the table exists in multiple schemas, all instances are used as reference points.

    .PARAMETER ExcludeViews
        Excludes views from both the reference objects and the comparison results, focusing only on physical tables.
        Use this when you need to find similar table structures for data migration or archiving where views aren't relevant.

    .PARAMETER IncludeSystemDatabases
        Includes system databases (master, model, msdb, tempdb) in the similarity search.
        Typically used when troubleshooting system table relationships or comparing custom objects in system databases.

    .PARAMETER MatchPercentThreshold
        Sets the minimum percentage of matching column names required to include a table pair in results.
        Use values like 50 for loose matches, 80 for close structural similarity, or 95 for near-identical tables.
        Zero matches are always excluded regardless of this threshold.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Table, Lookup
        Author: Jana Sattainathan (@SQLJana), sqljana.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaSimilarTable

    .OUTPUTS
        PSCustomObject

        Returns one object per matching table pair found. Each object represents one source table matched against one similar table. All properties are displayed by default (no Select-DefaultView applied).

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Table: The fully qualified name of the source table (database.schema.table)
        - MatchingTable: The fully qualified name of the matching table found (database.schema.table)
        - MatchPercent: Percentage of matching column names between the two tables (0-100)
        - OriginalDatabaseName: Name of the database containing the source table
        - OriginalDatabaseId: System database ID for the source table's database
        - OriginalSchemaName: Name of the schema containing the source table
        - OriginalTableName: Name of the source table
        - OriginalTableNameRankInDB: Dense ranking of the table among all tables in its database (used for processing order)
        - OriginalTableType: Type of the source table (TABLE or VIEW)
        - OriginalColumnCount: Number of columns in the source table
        - MatchingDatabaseName: Name of the database containing the matching table
        - MatchingDatabaseId: System database ID for the matching table's database
        - MatchingSchemaName: Name of the schema containing the matching table
        - MatchingTableName: Name of the matching table
        - MatchingTableType: Type of the matching table (TABLE or VIEW)
        - MatchingColumnCount: Number of columns in the matching table

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01

        Searches all user database tables and views for each, returns all tables or views with their matching tables/views and match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks

        Searches AdventureWorks database and lists tables/views and their corresponding matching tables/views with match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks -SchemaName HumanResource

        Searches AdventureWorks database and lists tables/views in the HumanResource schema with their corresponding matching tables/views with match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks -SchemaName HumanResource -Table Employee

        Searches AdventureWorks database and lists tables/views in the HumanResource schema and table Employee with its corresponding matching tables/views with match percent

    .EXAMPLE
        PS C:\> Find-DbaSimilarTable -SqlInstance DEV01 -Database AdventureWorks -MatchPercentThreshold 60

        Searches AdventureWorks database and lists all tables/views with its corresponding matching tables/views with match percent greater than or equal to 60

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [string]$SchemaName,
        [string]$TableName,
        [switch]$ExcludeViews,
        [switch]$IncludeSystemDatabases,
        [int]$MatchPercentThreshold,
        [switch]$EnableException
    )

    begin {
        $everyServerVwCount = 0

        $sqlSelect = "WITH ColCountsByTable
                AS
                (
                      SELECT
                            c.TABLE_CATALOG,
                            c.TABLE_SCHEMA,
                            c.TABLE_NAME,
                            COUNT(1) AS Column_Count
                      FROM INFORMATION_SCHEMA.COLUMNS c
                      GROUP BY
                            c.TABLE_CATALOG,
                            c.TABLE_SCHEMA,
                            c.TABLE_NAME
                )
                SELECT
                      100 * COUNT(c2.COLUMN_NAME) /*Matching_Column_Count*/ / MIN(ColCountsByTable.Column_Count) /*Column_Count*/ AS MatchPercent,
                      DENSE_RANK() OVER(ORDER BY c.TABLE_CATALOG, c.TABLE_SCHEMA, c.TABLE_NAME) TableNameRankInDB,
                      c.TABLE_CATALOG AS DatabaseName,
                      (SELECT database_id FROM sys.databases WHERE name = c.TABLE_CATALOG) AS DatabaseId,
                      c.TABLE_SCHEMA AS SchemaName,
                      c.TABLE_NAME AS TableName,
                      t.TABLE_TYPE AS TableType,
                      MIN(ColCountsByTable.Column_Count) AS ColumnCount,
                      c2.TABLE_CATALOG AS MatchingDatabaseName,
                      (SELECT database_id FROM sys.databases WHERE name = c2.TABLE_CATALOG) AS MatchingDatabaseId,
                      c2.TABLE_SCHEMA AS MatchingSchemaName,
                      c2.TABLE_NAME AS MatchingTableName,
                      t2.TABLE_TYPE AS MatchingTableType,
                      COUNT(c2.COLUMN_NAME) AS MatchingColumnCount
                FROM INFORMATION_SCHEMA.TABLES t
                      INNER JOIN INFORMATION_SCHEMA.COLUMNS c
                            ON t.TABLE_CATALOG = c.TABLE_CATALOG
                                  AND t.TABLE_SCHEMA = c.TABLE_SCHEMA
                                  AND t.TABLE_NAME = c.TABLE_NAME
                      INNER JOIN ColCountsByTable
                            ON t.TABLE_CATALOG = ColCountsByTable.TABLE_CATALOG
                                  AND t.TABLE_SCHEMA = ColCountsByTable.TABLE_SCHEMA
                                  AND t.TABLE_NAME = ColCountsByTable.TABLE_NAME
                      LEFT OUTER JOIN INFORMATION_SCHEMA.COLUMNS c2
                            ON t.TABLE_NAME != c2.TABLE_NAME
                                  AND c.COLUMN_NAME = c2.COLUMN_NAME
                      LEFT JOIN INFORMATION_SCHEMA.TABLES t2
                            ON c2.TABLE_NAME = t2.TABLE_NAME"

        $sqlWhere = "
                WHERE "

        $sqlGroupBy = "
                GROUP BY
                      c.TABLE_CATALOG,
                      c.TABLE_SCHEMA,
                      c.TABLE_NAME,
                      t.TABLE_TYPE,
                      c2.TABLE_CATALOG,
                      c2.TABLE_SCHEMA,
                      c2.TABLE_NAME,
                      t2.TABLE_TYPE "

        $sqlHaving = "
                HAVING
                    /*Match_Percent should be greater than 0 at minimum!*/
                    "

        $sqlOrderBy = "
                ORDER BY
                      MatchPercent DESC"


        $sql = ''
        $wherearray = @()

        if ($ExcludeViews) {
            $wherearray += " (t.TABLE_TYPE <> 'VIEW' AND t2.TABLE_TYPE <> 'VIEW') "
        }

        if ($SchemaName) {
            $wherearray += (" (c.TABLE_SCHEMA = '{0}') " -f $SchemaName.Replace("'", "''")) #Replace single quotes with two single quotes!
        }

        if ($TableName) {
            $wherearray += (" (c.TABLE_NAME = '{0}') " -f $TableName.Replace("'", "''")) #Replace single quotes with two single quotes!

        }

        if ($wherearray.length -gt 0) {
            $sqlWhere = "$sqlWhere " + ($wherearray -join " AND ")
        } else {
            $sqlWhere = ""
        }


        $matchThreshold = 0
        if ($MatchPercentThreshold) {
            $matchThreshold = $MatchPercentThreshold
        } else {
            $matchThreshold = 0
        }

        $sqlHaving += (" (100 * COUNT(c2.COLUMN_NAME) / MIN(ColCountsByTable.Column_Count) >= {0}) " -f $matchThreshold)



        $sql = "$sqlSelect $sqlWhere $sqlGroupBy $sqlHaving $sqlOrderBy"

        Write-Message -Level Debug -Message $sql

    }

    process {
        foreach ($Instance in $SqlInstance) {

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }


            #Use IsAccessible instead of Status -eq 'normal' because databases that are on readable secondaries for AG or mirroring replicas will cause errors to be thrown
            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true }
            } else {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true -and $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $server.Databases | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }


            $totalCount = 0
            $dbCount = $dbs.count
            foreach ($db in $dbs) {

                Write-Message -Level Verbose -Message "Searching on database $db"
                $rows = $db.Query($sql)

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        ComputerName              = $server.ComputerName
                        InstanceName              = $server.ServiceName
                        SqlInstance               = $server.DomainInstanceName
                        Table                     = "$($row.DatabaseName).$($row.SchemaName).$($row.TableName)"
                        MatchingTable             = "$($row.MatchingDatabaseName).$($row.MatchingSchemaName).$($row.MatchingTableName)"
                        MatchPercent              = $row.MatchPercent
                        OriginalDatabaseName      = $row.DatabaseName
                        OriginalDatabaseId        = $row.DatabaseId
                        OriginalSchemaName        = $row.SchemaName
                        OriginalTableName         = $row.TableName
                        OriginalTableNameRankInDB = $row.TableNameRankInDB
                        OriginalTableType         = $row.TableType
                        OriginalColumnCount       = $row.ColumnCount
                        MatchingDatabaseName      = $row.MatchingDatabaseName
                        MatchingDatabaseId        = $row.MatchingDatabaseId
                        MatchingSchemaName        = $row.MatchingSchemaName
                        MatchingTableName         = $row.MatchingTableName
                        MatchingTableType         = $row.MatchingTableType
                        MatchingColumnCount       = $row.MatchingColumnCount
                    }
                }

                $vwCount = $vwCount + $rows.Count
                $totalCount = $totalCount + $rows.Count
                $everyServerVwCount = $everyServerVwCount + $rows.Count

                Write-Message -Level Verbose -Message "Found $vwCount tables/views in $db"
            }

            Write-Message -Level Verbose -Message "Found $totalCount total tables/views in $dbCount databases"
        }
    }
    end {
        Write-Message -Level Verbose -Message "Found $everyServerVwCount total tables/views"
    }
}