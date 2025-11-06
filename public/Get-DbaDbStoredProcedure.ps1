function Get-DbaDbStoredProcedure {
    <#
    .SYNOPSIS
        Retrieves stored procedures from SQL Server databases with detailed metadata and filtering options

    .DESCRIPTION
        Retrieves stored procedures from one or more SQL Server databases, returning detailed information including schema, creation dates, and implementation details. This function helps DBAs inventory stored procedures across instances, analyze database objects for documentation or migration planning, and locate specific procedures by name or schema. You can filter results by database, schema, or procedure name, and exclude system stored procedures to focus on user-defined objects. Supports multi-part naming conventions for precise targeting of specific procedures.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for stored procedures. Accepts database names and supports wildcards.
        Use this when you need to focus on specific databases instead of searching across all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specified databases from the stored procedure search. Accepts database names and supports wildcards.
        Useful when you want results from most databases but need to skip specific ones like development or staging databases.

    .PARAMETER ExcludeSystemSp
        Excludes system stored procedures from results, showing only user-defined stored procedures.
        Use this when you want to focus on custom business logic and avoid the hundreds of built-in SQL Server system procedures.

    .PARAMETER Name
        Specifies exact stored procedure names to retrieve. Supports two-part names (schema.procedure) and three-part names (database.schema.procedure).
        Use this when searching for specific procedures by name rather than browsing all procedures in a database or schema.

    .PARAMETER Schema
        Filters results to stored procedures within the specified schema(s). Accepts multiple schema names.
        Useful for organizing results by application area or when working with multi-tenant databases that separate objects by schema.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline processing.
        Use this to chain commands when you need to filter databases first, then retrieve stored procedures from the filtered results.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, StoredProcedure, Proc
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbStoredProcedure

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance sql2016

        Gets all database Stored Procedures

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -Database db1

        Gets the Stored Procedures for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -ExcludeDatabase db1

        Gets the Stored Procedures for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -ExcludeSystemSp

        Gets the Stored Procedures for all databases that are not system objects

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbStoredProcedure

        Gets the Stored Procedures for the databases on Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance Server1 -ExcludeSystem | Get-DbaDbStoredProcedure

        Pipe the databases from Get-DbaDatabase into Get-DbaDbStoredProcedure

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -Database db1 -Name schema1.proc1

        Gets the Stored Procedure proc1 in the schema1 schema in the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -Name db1.schema1.proc1

        Gets the Stored Procedure proc1 in the schema1 schema in the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -Database db1 -Name proc1

        Gets the Stored Procedure proc1 in the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance Server1 -Database db1 -Schema schema1

        Gets the Stored Procedures in schema1 for the db1 database

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemSp,
        [string[]]$Name,
        [string[]]$Schema,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Name) {
            $fqtns = @()
            foreach ($t in $Name) {
                $fqtn = Get-ObjectNameParts -ObjectName $t

                if (!$fqtn.Parsed) {
                    Write-Message -Level Warning -Message "Please check you are using proper two-part or three-part names. If your search value contains special characters you must use [ ] to wrap the name. The value $t could not be parsed as a valid name."
                    Continue
                }

                $fqtns += [PSCustomObject] @{
                    Database   = $fqtn.Database
                    Schema     = $fqtn.Schema
                    Procedure  = $fqtn.Name
                    InputValue = $fqtn.InputValue
                }
            }
            if (!$fqtns) {
                Stop-Function -Message "No valid procedure name specified"
                return
            }
        }
    }
    process {
        if (Test-Bound SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        $ExcludeSystemSpIsBound = Test-Bound -ParameterName ExcludeSystemSp

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }

            # Let the SMO read all properties referenced in this command for all stored procedures in the database in one query.
            # Downside: If some other properties were already read outside of this command in the used SMO, they are cleared.
            $db.StoredProcedures.ClearAndInitialize('', [string[]]('Schema', 'Name', 'ID', 'CreateDate', 'DateLastModified', 'ImplementationType', 'Startup', 'IsSystemObject'))

            if ($db.StoredProcedures.Count -eq 0) {
                Write-Message -Message "No Stored Procedures exist in the $db database on $instance" -Target $db -Level Output
                continue
            }

            if ($fqtns) {
                $procs = @()
                foreach ($fqtn in $fqtns) {
                    # If the user specified a database in a three-part name, and it's not the
                    # database currently being processed, skip this procedure.
                    if ($fqtn.Database) {
                        if ($fqtn.Database -ne $db.Name) {
                            continue
                        }
                    }

                    $p = $db.StoredProcedures | Where-Object { $_.Name -in $fqtn.Procedure -and $fqtn.Schema -in ($_.Schema, $null) -and $fqtn.Database -in ($_.Parent.Name, $null) }

                    if (-not $p) {
                        Write-Message -Level Verbose -Message "Could not find procedure $($fqtn.Name) in $db on $server"
                    }

                    $procs += $p
                }
            } else {
                $procs = $db.StoredProcedures
            }

            if ($Schema) {
                $procs = $procs | Where-Object { $_.Schema -in $Schema }
            }

            foreach ($proc in $procs) {
                if ($ExcludeSystemSpIsBound -and $proc.IsSystemObject ) {
                    continue
                }

                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name ComputerName -value $proc.Parent.ComputerName
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name InstanceName -value $proc.Parent.InstanceName
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name SqlInstance -value $proc.Parent.SqlInstance
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name Database -value $db.Name
                Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name DatabaseId -value $db.Id

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'ID as ObjectId', 'CreateDate',
                'DateLastModified', 'Name', 'ImplementationType', 'Startup'
                Select-DefaultView -InputObject $proc -Property $defaults
            }
        }
    }
}