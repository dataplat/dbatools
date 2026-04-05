function Find-DbaObject {
    <#
    .SYNOPSIS
        Searches database objects by name or column name across SQL Server databases using regex patterns.

    .DESCRIPTION
        Provides a unified search across all database object types (tables, views, stored procedures, functions,
        synonyms, triggers) by matching their names against a regex pattern. Optionally extends the search to
        column names within tables and views. This complements the existing Find-DbaStoredProcedure, Find-DbaView,
        and Find-DbaTrigger commands which search object definition text rather than object or column names.

        Uses T-SQL queries against sys.objects and sys.columns for optimal performance. Pattern matching is
        performed in PowerShell using full regex syntax.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory -
        Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more databases to search. When omitted, searches all user databases on the instance.
        Use this to focus searches on specific databases when you know where the objects are located.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during the search. Accepts multiple database names.
        Use this to exclude large databases or test environments from the search.

    .PARAMETER Pattern
        The regular expression pattern to match against object names (and optionally column names).
        Supports full regex syntax for complex pattern matching. For example, use "^Customer" to find objects
        starting with "Customer", or "Service|Product" to find objects mentioning either term.

    .PARAMETER ObjectType
        Filters the search to specific object types. Accepts one or more of:
        - Table: User tables (sys.objects type U)
        - View: Views (sys.objects type V)
        - StoredProcedure: Stored procedures (sys.objects type P)
        - ScalarFunction: Scalar-valued functions (sys.objects type FN)
        - TableValuedFunction: Inline and multi-statement table-valued functions (sys.objects type IF/TF)
        - Synonym: Synonyms (sys.objects type SN)
        - Trigger: SQL triggers (sys.objects type TR)
        - All: All of the above (default)

    .PARAMETER IncludeColumns
        When specified, additionally searches column names within tables and views for the given pattern.
        Results with column name matches include a MatchType of "ColumnName" and the matching column name.
        This is useful for finding which tables or views contain a column related to a specific domain concept.

    .PARAMETER IncludeSystemObjects
        Includes system objects (those shipped with SQL Server) in the search results.
        By default, only user-created objects are searched.

    .PARAMETER IncludeSystemDatabases
        Includes system databases (master, model, msdb, tempdb) in the search scope.
        By default, only user databases are searched.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Object, Lookup, Find
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaObject

    .OUTPUTS
        PSCustomObject

        Returns one object per match found. When -IncludeColumns is used, there may be multiple results
        per database object (one for the object name match plus one per matching column name).

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - SqlInstance: The SQL Server instance name
        - Database: The database containing the matched object
        - Schema: The schema of the matched object
        - Name: The name of the matched object
        - ObjectType: The SQL Server type description (e.g., USER_TABLE, VIEW, SQL_STORED_PROCEDURE)
        - MatchType: "ObjectName" when the object name matched, "ColumnName" when a column name matched
        - ColumnName: The matching column name when MatchType is "ColumnName", otherwise null
        - CreateDate: DateTime when the object was created
        - LastModified: DateTime when the object was last modified

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance DEV01 -Pattern Service

        Searches all user databases on DEV01 for any object whose name contains "Service".

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance DEV01 -Pattern Service -IncludeColumns

        Searches all user databases on DEV01 for objects named with "Service" and tables/views
        that have columns whose names contain "Service".

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance DEV01 -Pattern "^Customer" -ObjectType Table

        Finds all user tables on DEV01 whose names start with "Customer".

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance DEV01 -Pattern "Invoice" -Database Accounting -IncludeColumns

        Searches the Accounting database for objects and columns related to "Invoice".

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance sql2019 -Pattern "Service|Product" -ObjectType Table, View

        Finds all tables and views whose names contain either "Service" or "Product".

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(Mandatory)]
        [string]$Pattern,
        [ValidateSet("Table", "View", "StoredProcedure", "ScalarFunction", "TableValuedFunction", "Synonym", "Trigger", "All")]
        [string[]]$ObjectType = @("All"),
        [switch]$IncludeColumns,
        [switch]$IncludeSystemObjects,
        [switch]$IncludeSystemDatabases,
        [switch]$EnableException
    )

    begin {
        $typeCodeMap = @{
            "Table"               = @("'U'")
            "View"                = @("'V'")
            "StoredProcedure"     = @("'P'")
            "ScalarFunction"      = @("'FN'")
            "TableValuedFunction" = @("'IF'", "'TF'")
            "Synonym"             = @("'SN'")
            "Trigger"             = @("'TR'")
        }

        if ("All" -in $ObjectType) {
            $typeFilter = "'U', 'V', 'P', 'FN', 'IF', 'TF', 'SN', 'TR'"
        } else {
            $typeCodes = @()
            foreach ($type in $ObjectType) {
                $typeCodes += $typeCodeMap[$type]
            }
            $typeFilter = ($typeCodes | Select-Object -Unique) -join ", "
        }

        $sysFilter = if ($IncludeSystemObjects) { "" } else { "AND o.is_ms_shipped = 0" }

        $sqlObjects = "
            SELECT
                OBJECT_SCHEMA_NAME(o.object_id) AS SchemaName,
                o.name                          AS ObjectName,
                RTRIM(o.type)                   AS ObjectTypeCode,
                o.type_desc                     AS ObjectType,
                o.create_date                   AS CreateDate,
                o.modify_date                   AS LastModified
            FROM sys.objects o
            WHERE o.type IN ($typeFilter)
            $sysFilter"

        $sqlColumns = "
            SELECT
                OBJECT_SCHEMA_NAME(c.object_id) AS SchemaName,
                OBJECT_NAME(c.object_id)        AS ObjectName,
                RTRIM(o.type)                   AS ObjectTypeCode,
                o.type_desc                     AS ObjectType,
                o.create_date                   AS CreateDate,
                o.modify_date                   AS LastModified,
                c.name                          AS ColumnName
            FROM sys.columns c
            INNER JOIN sys.objects o ON c.object_id = o.object_id
            WHERE o.type IN ($typeFilter)
            $sysFilter"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.versionMajor -lt 9) {
                Write-Message -Level Warning -Message "This command only supports SQL Server 2005 and above."
                Continue
            }

            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" }
            } else {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" -and $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Searching object names in database $db on $instance"

                Write-Message -Level Debug -Message $sqlObjects
                $objectRows = $db.ExecuteWithResults($sqlObjects).Tables.Rows

                foreach ($row in $objectRows) {
                    if ($row.ObjectName -match $Pattern) {
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            SqlInstance  = $server.ServiceName
                            Database     = $db.Name
                            Schema       = $row.SchemaName
                            Name         = $row.ObjectName
                            ObjectType   = $row.ObjectType
                            MatchType    = "ObjectName"
                            ColumnName   = $null
                            CreateDate   = $row.CreateDate
                            LastModified = $row.LastModified
                        }
                    }
                }

                if ($IncludeColumns) {
                    Write-Message -Level Verbose -Message "Searching column names in database $db on $instance"

                    Write-Message -Level Debug -Message $sqlColumns
                    $columnRows = $db.ExecuteWithResults($sqlColumns).Tables.Rows

                    foreach ($row in $columnRows) {
                        if ($row.ColumnName -match $Pattern) {
                            [PSCustomObject]@{
                                ComputerName = $server.ComputerName
                                SqlInstance  = $server.ServiceName
                                Database     = $db.Name
                                Schema       = $row.SchemaName
                                Name         = $row.ObjectName
                                ObjectType   = $row.ObjectType
                                MatchType    = "ColumnName"
                                ColumnName   = $row.ColumnName
                                CreateDate   = $row.CreateDate
                                LastModified = $row.LastModified
                            }
                        }
                    }
                }
            }
        }
    }
}
