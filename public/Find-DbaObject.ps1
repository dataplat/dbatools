function Find-DbaObject {
    <#
    .SYNOPSIS
        Searches for database objects by name or column name across multiple object types using pattern matching.

    .DESCRIPTION
        Provides a unified search across SQL Server database objects including tables, views, stored procedures, functions, and more. Searches object names using regular expressions and optionally searches column names within tables and views. This is the "global search" command for finding any database object matching a pattern, making it easy to locate objects without knowing their exact type or location.

        Unlike the existing Find-Dba* commands that search within object definitions (source code), this command searches for objects by their names and optionally by column names they contain. Perfect for discovering all objects related to a business concept (e.g., "Customer", "Invoice", "Service") across your entire database instance.

        Use the ObjectType parameter to limit searches to specific object types like tables or procedures. Use IncludeColumns to also search column names within tables and views, helping you find tables that contain specific data elements.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for objects matching the pattern. Accepts database names and supports wildcards.
        When omitted, searches all user databases on the instance. Use this to focus searches on specific databases when you know where objects are located.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during the object search. Accepts database names and supports wildcards.
        Use this when you want to search most databases but exclude specific ones like test environments or archived databases.

    .PARAMETER Pattern
        Specifies the regular expression pattern to search for in object names (and optionally column names if IncludeColumns is specified).
        Supports full regex syntax for complex pattern matching. Use this to find all objects related to a business concept or feature.

    .PARAMETER ObjectType
        Limits the search to specific object types. Valid values include:
        - Table (U)
        - View (V)
        - StoredProcedure (P)
        - Function (FN, IF, TF)
        - Synonym (SN)
        - All (default - searches all object types)

        Use this to narrow your search when you know what type of object you're looking for.

    .PARAMETER IncludeColumns
        When specified, also searches for the pattern in column names within tables and views.
        This helps you find tables and views that contain columns matching your pattern, such as finding all tables with a "ServiceId" column.

    .PARAMETER IncludeSystemObjects
        Includes system objects (those shipped with SQL Server) in the search results. By default, only user-created objects are searched.
        Use this when investigating system objects or when patterns might exist in Microsoft-provided code.

    .PARAMETER IncludeSystemDatabases
        Includes system databases (master, model, msdb, tempdb) in the search scope. By default, only user databases are searched.
        Use this when investigating system objects or when your pattern might exist in system databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Object, Table, View, StoredProcedure, Function, Lookup
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaObject

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance DEV01 -Pattern Service

        Searches all user databases for any objects (tables, views, procedures, functions, etc.) with "Service" in their name.

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance DEV01 -Pattern Service -IncludeColumns

        Searches all user databases for objects named "Service" and also finds tables/views that have columns with "Service" in the column name.

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance DEV01 -Pattern "^Customer" -ObjectType Table

        Searches for tables whose names start with "Customer" across all user databases.

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance DEV01 -Pattern "Invoice" -Database Accounting -IncludeColumns

        Searches the Accounting database for all objects and columns containing "Invoice".

    .EXAMPLE
        PS C:\> Find-DbaObject -SqlInstance sql2016 -Pattern "email|phone" -ObjectType Table,View -IncludeColumns

        Searches for tables and views that either have "email" or "phone" in their name or column names.

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
        [ValidateSet("All", "Table", "View", "StoredProcedure", "Function", "Synonym")]
        [string[]]$ObjectType = "All",
        [switch]$IncludeColumns,
        [switch]$IncludeSystemObjects,
        [switch]$IncludeSystemDatabases,
        [switch]$EnableException
    )

    begin {
        # Build the type filter based on ObjectType parameter
        $typeFilter = ""
        if ("All" -notin $ObjectType) {
            $types = New-Object System.Collections.ArrayList
            if ("Table" -in $ObjectType) { $null = $types.Add("'U'") }
            if ("View" -in $ObjectType) { $null = $types.Add("'V'") }
            if ("StoredProcedure" -in $ObjectType) { $null = $types.Add("'P'") }
            if ("Function" -in $ObjectType) { $null = $types.Add("'FN'"); $null = $types.Add("'IF'"); $null = $types.Add("'TF'") }
            if ("Synonym" -in $ObjectType) { $null = $types.Add("'SN'") }

            if ($types.Count -gt 0) {
                $typeFilter = "AND o.type IN ($($types -join ','))"
            }
        } else {
            # Search common user object types
            $typeFilter = "AND o.type IN ('U','V','P','FN','IF','TF','SN')"
        }

        # SQL to find objects by name
        $sqlObjects = @"
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS ObjectName,
    o.object_id AS ObjectId,
    CASE o.type
        WHEN 'U' THEN 'Table'
        WHEN 'V' THEN 'View'
        WHEN 'P' THEN 'StoredProcedure'
        WHEN 'FN' THEN 'Function'
        WHEN 'IF' THEN 'Function'
        WHEN 'TF' THEN 'Function'
        WHEN 'SN' THEN 'Synonym'
        ELSE o.type_desc
    END AS ObjectType,
    o.create_date AS CreateDate,
    o.modify_date AS ModifyDate,
    'ObjectName' AS MatchType
FROM sys.objects o
WHERE 1=1
$typeFilter
"@

        if (!$IncludeSystemObjects) {
            $sqlObjects += "`nAND o.is_ms_shipped = 0"
        }

        # SQL to find columns by name (only for tables and views)
        $sqlColumns = @"
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS ObjectName,
    o.object_id AS ObjectId,
    CASE o.type
        WHEN 'U' THEN 'Table'
        WHEN 'V' THEN 'View'
        ELSE o.type_desc
    END AS ObjectType,
    o.create_date AS CreateDate,
    o.modify_date AS ModifyDate,
    'ColumnName' AS MatchType,
    c.name AS ColumnName
FROM sys.objects o
INNER JOIN sys.columns c ON o.object_id = c.object_id
WHERE o.type IN ('U','V')
"@

        if (!$IncludeSystemObjects) {
            $sqlColumns += "`nAND o.is_ms_shipped = 0"
        }

        $everyserverobjectcount = 0
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "This command only supports SQL Server 2005 and above." -Continue
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

            $totalcount = 0
            $dbcount = $dbs.Count
            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Searching database $db for objects matching pattern: $Pattern"

                # Search for objects by name
                Write-Message -Level Debug -Message $sqlObjects
                $rows = $db.ExecuteWithResults($sqlObjects).Tables.Rows

                foreach ($row in $rows) {
                    Write-Message -Level Debug -Message "Checking object: $($row.SchemaName).$($row.ObjectName)"
                    if ($row.ObjectName -match $Pattern) {
                        $totalcount++; $everyserverobjectcount++

                        [PSCustomObject]@{
                            ComputerName   = $server.ComputerName
                            InstanceName   = $server.ServiceName
                            SqlInstance    = $server.DomainInstanceName
                            Database       = $db.Name
                            SchemaName     = $row.SchemaName
                            ObjectName     = $row.ObjectName
                            ObjectType     = $row.ObjectType
                            MatchType      = $row.MatchType
                            ColumnName     = $null
                            CreateDate     = $row.CreateDate
                            ModifyDate     = $row.ModifyDate
                        } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
                    }
                }

                # Search for columns by name if requested
                if ($IncludeColumns) {
                    Write-Message -Level Verbose -Message "Searching database $db for columns matching pattern: $Pattern"
                    Write-Message -Level Debug -Message $sqlColumns
                    $columnRows = $db.ExecuteWithResults($sqlColumns).Tables.Rows

                    foreach ($row in $columnRows) {
                        Write-Message -Level Debug -Message "Checking column: $($row.SchemaName).$($row.ObjectName).$($row.ColumnName)"
                        if ($row.ColumnName -match $Pattern) {
                            $totalcount++; $everyserverobjectcount++

                            [PSCustomObject]@{
                                ComputerName   = $server.ComputerName
                                InstanceName   = $server.ServiceName
                                SqlInstance    = $server.DomainInstanceName
                                Database       = $db.Name
                                SchemaName     = $row.SchemaName
                                ObjectName     = $row.ObjectName
                                ObjectType     = $row.ObjectType
                                MatchType      = $row.MatchType
                                ColumnName     = $row.ColumnName
                                CreateDate     = $row.CreateDate
                                ModifyDate     = $row.ModifyDate
                            } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Found $totalcount matching objects/columns in $db"
            }
            Write-Message -Level Verbose -Message "Searched $dbcount databases on $instance"
        }
    }

    end {
        Write-Message -Level Verbose -Message "Found $everyserverobjectcount total matching objects/columns across all instances"
    }
}
