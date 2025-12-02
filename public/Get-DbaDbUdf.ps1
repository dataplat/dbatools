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

                # Let the SMO read all properties referenced in this command for all user defined functions in the database in one query.
                # Downside: If some other properties were already read outside of this command in the used SMO, they are cleared.
                $db.UserDefinedFunctions.ClearAndInitialize('', [string[]]('Schema', 'Name', 'CreateDate', 'DateLastModified', 'DataType', 'IsSystemObject'))

                # UserDefinedAggregates don't have IsSystemObject property, so initialize separately
                $db.UserDefinedAggregates.ClearAndInitialize('', [string[]]('Schema', 'Name', 'CreateDate', 'DateLastModified', 'DataType'))

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