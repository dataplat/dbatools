function Get-DbaModule {
    <#
    .SYNOPSIS
        Displays all objects in sys.sys_modules after specified modification date.  Works on SQL Server 2008 and above.

    .DESCRIPTION
        Quickly find modules (Stored Procs, Functions, Views, Constraints, Rules, Triggers, etc) that have been modified in a database, or across all databases.
        Results will exclude the module definition, but can be queried explicitly.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude.

    .PARAMETER ModifiedSince
        DateTime value to use as minimum modified date of module.

    .PARAMETER Type
        Limit by specific type of module. Valid choices include: View, TableValuedFunction, DefaultConstraint, StoredProcedure, Rule, InlineTableValuedFunction, Trigger, ScalarFunction

    .PARAMETER ExcludeSystemDatabases
        Allows you to suppress output on system databases

    .PARAMETER ExcludeSystemObjects
        Allows you to suppress output on system objects

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: StoredProcedure, Trigger
        Author: Brandon Abshire, netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaModule

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
         OBJECTPROPERTY(so.object_id, 'ExecIsStartUp') as startup
        FROM sys.sql_modules sm
        LEFT JOIN sys.objects so ON sm.object_id = so.object_id
        WHERE so.modify_date >= '$($ModifiedSince)'"
        if ($ExcludeSystemObjects) {
            $sql += "`n AND so.is_ms_shipped = 0"
        }
        if ($Type) {
            $sqltypes = $types -join "','"
            $sql += " AND type_desc in ('$sqltypes')"
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