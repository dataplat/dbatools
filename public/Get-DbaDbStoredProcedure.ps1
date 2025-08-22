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
        To get Stored Procedures from specific database(s)

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto populated from the server

    .PARAMETER ExcludeSystemSp
        This switch removes all system objects from the Stored Procedure collection

    .PARAMETER Name
        Name(s) of the stored procedure(s) to return. It is possible to specify two-part names such as schemaname.procname and three-part names such as dbname.schemaname.procname.

    .PARAMETER Schema
        Only return procedures from the specified schema.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

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