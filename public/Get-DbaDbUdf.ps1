function Get-DbaDbUdf {
    <#
    .SYNOPSIS
        Retrieves User Defined Functions from SQL Server databases with filtering and metadata

    .DESCRIPTION
        Retrieves all User Defined Functions (UDFs) from one or more SQL Server databases, returning detailed metadata including schema, creation dates, and data types. This function helps DBAs inventory custom database logic, analyze code dependencies during migrations, and audit user-created functions for security or performance reviews. You can filter results by database, schema, or function name, and exclude system functions to focus on custom business logic.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        To get User Defined Functions from specific database(s)

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto populated from the server

    .PARAMETER ExcludeSystemUdf
        This switch removes all system objects from the UDF collection

    .PARAMETER Schema
        The schema(s) to process. If unspecified, all schemas will be processed.

    .PARAMETER ExcludeSchema
        The schema(s) to exclude.

    .PARAMETER Name
        The name(s) of the user defined functions to process. If unspecified, all user defined functions will be processed.

    .PARAMETER ExcludeName
        The name(s) of the user defined functions to exclude.

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

        Gets all database User Defined Functions

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance Server1 -Database db1

        Gets the User Defined Functions for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance Server1 -ExcludeDatabase db1

        Gets the User Defined Functions for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance Server1 -ExcludeSystemUdf

        Gets the User Defined Functions for all databases that are not system objects (there can be 100+ system User Defined Functions in each DB)

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbUdf

        Gets the User Defined Functions for the databases on Sql1 and Sql2/sqlexpress

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

                $userDefinedFunctions = $db.UserDefinedFunctions

                if (!$userDefinedFunctions) {
                    Write-Message -Message "No User Defined Functions exist in the $db database on $instance" -Target $db -Level Verbose
                    continue
                }
                if ($ExcludeSystemUdf) {
                    $userDefinedFunctions = $userDefinedFunctions | Where-Object IsSystemObject -eq $false
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