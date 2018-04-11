function Get-DbaSqlModule {
    <#
    .SYNOPSIS
    Displays all objects in sys.sys_modules after specified modification date.  Works on SQL Server 2008 and above.

    .DESCRIPTION
    Quickly find modules (Stored Procs, Functions, Views, Constraints, Rules, Triggers, etc) that have been modified in a database, or across all databases.
    Results will exclude the module definition, but can be queried explicitly.

    .PARAMETER SqlInstance
    Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
    Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Database
    The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
    The database(s) to exclude.

    .PARAMETER ModifiedSince
    DateTime value to use as minimum modified date of module.

    .PARAMETER Type
    Limit by specific type of module. Valid choices include: View, TableValuedFunction, DefaultConstraint, StoredProcedure, Rule, InlineTableValuedFunction, Trigger, ScalarFunction

    .PARAMETER NoSystemDb
    Allows you to suppress output on system databases

    .PARAMETER NoSystemObjects
    Allows you to suppress output on system objects

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Author: Brandon Abshire, netnerds.net
    Tags: StoredProcedure, Trigger

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Get-DbaSqlModule

    .EXAMPLE
    Get-DbaSqlModule -SqlServer sql2008, sqlserver2012
    Return all modules for servers sql2008 and sqlserver2012 sorted by Database, Modify_Date ASC.

    .EXAMPLE
    Get-DbaSqlModule -SqlServer sql2008, sqlserver2012 | Select *
    Shows hidden definition column (informative wall of text).

    .EXAMPLE
    Get-DbaSqlModule -SqlServer sql2008 -Database TestDB -ModifiedSince "01/01/2017 10:00:00 AM"
    Return all modules on server sql2008 for only the TestDB database with a modified date after 01/01/2017 10:00:00 AM.

    .EXAMPLE
    Get-DbaSqlModule -SqlServer sql2008 -Type View, Trigger, ScalarFunction
    Return all modules on server sql2008 for all databases that are triggers, views or scalar functions.
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [datetime]$ModifiedSince = "01/01/1900",
        [ValidateSet("View", "TableValuedFunction", "DefaultConstraint", "StoredProcedure", "Rule", "InlineTableValuedFunction", "Trigger", "ScalarFunction")]
        [string[]]$Type,
        [switch]$NoSystemDb,
        [switch]$NoSystemObjects,
        [Alias('Silent')]
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
        if ($NoSystemObjects) {
            $sql += "`n AND so.is_ms_shipped = 0"
        }
        if ($Type) {
            $sqltypes = $types -join "','"
            $sql += " AND type_desc in ('$sqltypes')"
        }
        $sql += "`n ORDER BY so.modify_date"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = Get-DbaDatabase -SqlInstance $server

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }


            foreach ($db in $databases) {

                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible. Skipping database." -Target $db -Continue
                }

                foreach ($row in $server.Query($sql, $db.name)) {
                    [PSCustomObject]@{
                        ComputerName  = $server.NetName
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
}