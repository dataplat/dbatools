function Get-DbaModule {
    <#
    .SYNOPSIS
        Retrieves database modules (stored procedures, functions, views, triggers) modified after a specified date

    .DESCRIPTION
        Queries sys.sql_modules and sys.objects to find database modules that have been modified within a specified timeframe, helping DBAs track recent code changes for troubleshooting, auditing, or deployment verification.
        Essential for identifying which stored procedures, functions, views, or triggers were altered during maintenance windows or after application deployments.
        Returns metadata including modification dates, schema names, and object types, with the actual module definition hidden by default but available when needed.
        Supports filtering by specific module types and can exclude system objects to focus on user-created code changes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for modified modules. Accepts database names or wildcards for pattern matching.
        Use this when you need to focus on specific databases rather than scanning all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the module search. Useful when you want to search most databases but skip certain ones like test or archive databases.
        Commonly used to exclude databases under maintenance or those known to have frequent module changes.

    .PARAMETER ModifiedSince
        Returns only modules modified after this date and time. Defaults to 1900-01-01 to include all modules.
        Essential for tracking recent code changes after deployments, maintenance windows, or troubleshooting sessions.

    .PARAMETER Type
        Filters results to specific module types only. Valid choices include: View, TableValuedFunction, DefaultConstraint, StoredProcedure, Rule, InlineTableValuedFunction, Trigger, ScalarFunction.
        Use this when investigating specific types of database objects, such as finding all modified stored procedures after an application release.

    .PARAMETER ExcludeSystemDatabases
        Excludes system databases (master, model, msdb, tempdb) from the search. Focus on user databases only.
        Recommended for routine auditing since system database changes are typically handled by SQL Server updates rather than application deployments.

    .PARAMETER ExcludeSystemObjects
        Excludes Microsoft-shipped system objects from results. Shows only user-created modules.
        Use this to filter out built-in SQL Server objects and focus on custom business logic that your team maintains.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline operations. Allows chaining commands together.
        Useful for complex filtering scenarios where you first select databases with specific criteria, then search for modules within those databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: General, Object, StoredProcedure, View, Table, Trigger
        Author: Brandon Abshire, netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaModule

    .OUTPUTS
        PSCustomObject

        Returns one object per database module (stored procedure, function, view, trigger, etc.) found in the specified databases that matches the filter criteria.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database containing the module
        - Name: The name of the module object
        - ObjectID: The SQL Server object ID (int)
        - SchemaName: The name of the schema containing the module
        - Type: The type of module (VIEW, SQL_STORED_PROCEDURE, SQL_SCALAR_FUNCTION, SQL_TABLE_VALUED_FUNCTION, SQL_INLINE_TABLE_VALUED_FUNCTION, SQL_TRIGGER, DEFAULT_CONSTRAINT, RULE)
        - CreateDate: DateTime when the module was first created
        - ModifyDate: DateTime when the module was last modified
        - IsMsShipped: Boolean indicating if the module is a Microsoft-shipped system object
        - ExecIsStartUp: Boolean indicating if the stored procedure is configured to run at SQL Server startup (for stored procedures only)
        - Definition: The source code definition of the module (hidden by default, use Select-Object * to view)

    .EXAMPLE
        PS C:\> Get-DbaModule -SqlInstance sql2008, sqlserver2012

        Return all modules for servers sql2008 and sqlserver2012 sorted by Database, Modify_Date ASC.

    .EXAMPLE
        PS C:\> Get-DbaModule -SqlInstance sql2008, sqlserver2012 | Select-Object *

        Shows hidden definition column (informative wall of text).

    .EXAMPLE
        PS C:\> Get-DbaModule -SqlInstance sql2008 -Database TestDB -ModifiedSince "2017-01-01 10:00:00"

        Return all modules on server sql2008 for only the TestDB database with a modified date after 1 January 2017 10:00:00 AM.

    .EXAMPLE
        PS C:\> Get-DbaModule -SqlInstance sql2008 -Type View, Trigger, ScalarFunction

        Return all modules on server sql2008 for all databases that are triggers, views or scalar functions.

    .EXAMPLE
        PS C:\> 'sql2008' | Get-DbaModule -Database TestDB -Type View, StoredProcedure, ScalarFunction

        Return all modules on server sql2008 for only the TestDB database that are stored procedures, views or scalar functions. Input via Pipeline

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2008 -ExcludeSystem | Get-DbaModule -Type View, Trigger, ScalarFunction

        Return all modules on server sql2008 for all user databases that are triggers, views or scalar functions.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2008, sqlserver2012 -ExcludeUser | Get-DbaModule -Type StoredProcedure -ExcludeSystemObjects

        Return all user created stored procedures in the system databases for servers sql2008 and sqlserver2012.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [datetime]$ModifiedSince = "1900-01-01",
        [ValidateSet("View", "TableValuedFunction", "DefaultConstraint", "StoredProcedure", "Rule", "InlineTableValuedFunction", "Trigger", "ScalarFunction")]
        [string[]]$Type,
        [switch]$ExcludeSystemDatabases,
        [switch]$ExcludeSystemObjects,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {

        $types = @()

        foreach ($t in $type) {
            if ($t -eq "View") { $types += "VIEW" }
            if ($t -eq "TableValuedFunction") { $types += "SQL_TABLE_VALUED_FUNCTION" }
            if ($t -eq "DefaultConstraint") { $types += "DEFAULT_CONSTRAINT" }
            if ($t -eq "StoredProcedure") { $types += "SQL_STORED_PROCEDURE" }
            if ($t -eq "Rule") { $types += "RULE" }
            if ($t -eq "InlineTableValuedFunction") { $types += "SQL_INLINE_TABLE_VALUED_FUNCTION" }
            if ($t -eq "Trigger") { $types += "SQL_TRIGGER" }
            if ($t -eq "ScalarFunction") { $types += "SQL_SCALAR_FUNCTION" }
        }


        $sql = "SELECT  DB_NAME() AS DatabaseName,
        so.name AS ModuleName,
        so.object_id ,
        SCHEMA_NAME(so.schema_id) AS SchemaName ,
        so.parent_object_id ,
        so.type ,
        so.type_desc ,
        so.create_date ,
        so.modify_date ,
        so.is_ms_shipped ,
        sm.definition,
         OBJECTPROPERTY(so.object_id, 'ExecIsStartUp') AS startup
        FROM sys.sql_modules sm
        LEFT JOIN sys.objects so ON sm.object_id = so.object_id
        WHERE so.modify_date >= '$($ModifiedSince)'"
        if ($ExcludeSystemObjects) {
            $sql += "`n AND so.is_ms_shipped = 0"
        }
        if ($Type) {
            $sqltypes = $types -join "','"
            $sql += " AND type_desc IN ('$sqltypes')"
        }
        $sql += "`n ORDER BY so.modify_date"
    }

    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            Write-Message -Level Verbose -Message "Creating InputObject from $SqlInstance"
            $InputObject += Get-DbaDatabase -SqlInstance $PSBoundParameters.SqlInstance -SqlCredential $PSBoundParameters.SqlCredential -Database $PSBoundParameters.Database -ExcludeDatabase $PSBoundParameters.ExcludeDatabase -ExcludeSystem:$PSBoundParameters.ExcludeSystemDatabases
        }

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }

            $server = $db.Parent
            Write-Message -Level Verbose -Message "Processing $db on $($server.DomainInstanceName)"

            foreach ($row in $server.Query($sql, $db.name)) {
                [PSCustomObject]@{
                    ComputerName  = $server.ComputerName
                    InstanceName  = $server.ServiceName
                    SqlInstance   = $server.DomainInstanceName
                    Database      = $row.DatabaseName
                    Name          = $row.ModuleName
                    ObjectID      = $row.object_id
                    SchemaName    = $row.SchemaName
                    Type          = $row.type_desc
                    CreateDate    = $row.create_date
                    ModifyDate    = $row.modify_date
                    IsMsShipped   = $row.is_ms_shipped
                    ExecIsStartUp = $row.startup
                    Definition    = $row.definition
                } | Select-DefaultView -ExcludeProperty Definition
            }
        }
    }
}