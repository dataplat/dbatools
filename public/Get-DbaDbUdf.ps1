function Get-DbaDbUdf {
    <#
    .SYNOPSIS
        Retrieves User Defined Functions and User Defined Aggregates from SQL Server databases with filtering and metadata

    .DESCRIPTION
        Retrieves all User Defined Functions (UDFs) and User Defined Aggregates from one or more SQL Server databases, returning detailed metadata including schema, creation dates, and data types. This function helps DBAs inventory custom database logic, analyze code dependencies during migrations, and audit user-created functions for security or performance reviews. You can filter results by database, schema, or function name, and exclude system functions to focus on custom business logic.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to retrieve User Defined Functions from. Accepts wildcards for pattern matching.
        Use this when you need to audit UDFs in specific databases rather than scanning the entire instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when retrieving User Defined Functions. Useful for excluding system databases or databases under maintenance.
        Commonly used to exclude tempdb, model, or large databases that don't contain custom business logic.

    .PARAMETER ExcludeSystemUdf
        Filters out built-in SQL Server system functions from the results, showing only custom user-created functions.
        Essential when auditing business logic since system databases can contain 100+ built-in UDFs that obscure custom code.

    .PARAMETER Schema
        Limits results to User Defined Functions within specific schemas. Accepts multiple schema names.
        Useful for focusing on functions owned by particular applications or development teams, such as 'Sales' or 'Reporting' schemas.

    .PARAMETER ExcludeSchema
        Excludes User Defined Functions from specific schemas when retrieving results.
        Helpful for filtering out legacy schemas, test schemas, or third-party application schemas that aren't relevant to your analysis.

    .PARAMETER Name
        Retrieves specific User Defined Functions by name. Accepts multiple function names and supports wildcards.
        Use this when searching for particular functions during troubleshooting or when documenting specific business logic components.

    .PARAMETER ExcludeName
        Excludes specific User Defined Functions from results by name. Supports wildcards for pattern matching.
        Useful for filtering out known test functions, deprecated functions, or utility functions that clutter audit reports.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Udf, Database
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbUdf

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.UserDefinedFunction, Microsoft.SqlServer.Management.Smo.UserDefinedAggregate

        Returns one object per User Defined Function or User Defined Aggregate found in the specified databases. Both SMO object types are combined in a single output stream, with UserDefinedAggregates always being user-created (no system aggregates exist in SQL Server).

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database containing the function/aggregate
        - Schema: The schema that contains the function/aggregate
        - CreateDate: DateTime when the function/aggregate was originally created
        - DateLastModified: DateTime of the most recent modification to the function/aggregate
        - Name: The name of the User Defined Function or User Defined Aggregate
        - DataType: The return data type of the function/aggregate (for example, 'int', 'varchar', 'table', etc.)

        Additional properties available from SMO (UserDefinedFunction):
        - IsSystemObject: Boolean indicating if this is a system-created object (True for system functions, False for user-created)
        - AssemblyName: Name of the .NET assembly if this is a CLR-based function
        - ClassName: Class name within the assembly for CLR-based functions
        - ExecutionContext: Whether function executes in caller or owner context
        - IsInlineTableValuedFunction: Boolean for inline table-valued functions
        - IsSqlTabular: Boolean indicating if this is a SQL table-valued function
        - QuotedIdentifierStatus: Boolean indicating quoted identifier setting
        - ReturnsNullOnNullInput: Boolean indicating NULL handling behavior
        - Text: The T-SQL source code or assembly reference of the function

        Note: UserDefinedAggregate objects do not have the IsSystemObject property. The -ExcludeSystemUdf switch filters out system functions but does not affect aggregates (which are never system objects).

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance sql2016

        Gets all database User Defined Functions and User Defined Aggregates

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance Server1 -Database db1

        Gets the User Defined Functions and User Defined Aggregates for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance Server1 -ExcludeDatabase db1

        Gets the User Defined Functions and User Defined Aggregates for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance Server1 -ExcludeSystemUdf

        Gets the User Defined Functions and User Defined Aggregates for all databases that are not system objects (there can be 100+ system User Defined Functions in each DB)

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbUdf

        Gets the User Defined Functions and User Defined Aggregates for the databases on Sql1 and Sql2/sqlexpress

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemUdf,
        [string[]]$Schema,
        [string[]]$ExcludeSchema,
        [string[]]$Name,
        [string[]]$ExcludeName,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $databases) {
                $server = $db.Parent

                # Let the SMO read all properties referenced in this command for all user defined functions in the database in one query.
                # Using SetDefaultInitFields + Refresh instead of ClearAndInitialize to respect SqlCredential
                try {
                    $initFieldsUdf = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsUdf.AddRange([string[]]('Schema', 'Name', 'CreateDate', 'DateLastModified', 'DataType', 'IsSystemObject'))
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedFunction], $initFieldsUdf)
                    $db.UserDefinedFunctions.Refresh()

                    # UserDefinedAggregates don't have IsSystemObject property, so initialize separately
                    $initFieldsUda = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsUda.AddRange([string[]]('Schema', 'Name', 'CreateDate', 'DateLastModified', 'DataType'))
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedAggregate], $initFieldsUda)
                    $db.UserDefinedAggregates.Refresh()
                } catch {
                    # If SetDefaultInitFields fails, fall back to lazy loading
                    Write-Message -Level Debug -Message "SetDefaultInitFields failed, using lazy loading: $_"
                }

                $userDefinedFunctions = $db.UserDefinedFunctions

                if ($ExcludeSystemUdf) {
                    $userDefinedFunctions = $userDefinedFunctions | Where-Object IsSystemObject -eq $false
                }

                # Combine UserDefinedFunctions and UserDefinedAggregates
                # UserDefinedAggregates are always user-created (no system aggregates exist)
                $userDefinedFunctions = @($userDefinedFunctions) + @($db.UserDefinedAggregates)

                if (!$userDefinedFunctions -or $userDefinedFunctions.Count -eq 0) {
                    Write-Message -Message "No User Defined Functions or Aggregates exist in the $db database on $instance" -Target $db -Level Verbose
                    continue
                }

                if ($Schema) {
                    $userDefinedFunctions = $userDefinedFunctions | Where-Object Schema -in $Schema
                }

                if ($ExcludeSchema) {
                    $userDefinedFunctions = $userDefinedFunctions | Where-Object Schema -notin $ExcludeSchema
                }

                if ($Name) {
                    $userDefinedFunctions = $userDefinedFunctions | Where-Object Name -in $Name
                }

                if ($ExcludeName) {
                    $userDefinedFunctions = $userDefinedFunctions | Where-Object Name -notin $ExcludeName
                }

                $userDefinedFunctions | ForEach-Object {

                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name Database -Value $db.Name

                    Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, Database, Schema, CreateDate, DateLastModified, Name, DataType
                }
            }
        }
    }
}