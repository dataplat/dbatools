function Get-DbaDbTable {
    <#
    .SYNOPSIS
        Retrieves table metadata including space usage, row counts, and table features from SQL Server databases

    .DESCRIPTION
        Returns detailed table information including row counts, space usage (IndexSpaceUsed, DataSpaceUsed), and special table characteristics like memory optimization, partitioning, and FileTable status. Essential for database capacity planning, documentation, and finding tables with specific features across multiple databases. Supports complex three-part naming with special characters and can filter by database, schema, or specific table names.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to retrieve table information from. Accepts multiple database names and wildcards.
        Use this when you need table data from specific databases instead of scanning all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from table retrieval. Accepts multiple database names and wildcards.
        Helpful when you want most databases but need to skip problematic or irrelevant ones like temp databases.

    .PARAMETER IncludeSystemDBs
        Includes system databases (master, model, msdb, tempdb) in the table scan.
        By default system databases are excluded since they rarely contain user tables of interest.

    .PARAMETER Table
        Specifies specific tables to retrieve using one, two, or three-part naming (table, schema.table, or database.schema.table).
        Use this when you need information on particular tables instead of all tables in the database.
        Wrap names containing special characters in square brackets and escape actual ] characters by doubling them.

    .PARAMETER Schema
        Filters results to tables within specific schemas. Accepts multiple schema names.
        Useful for focusing on application schemas while excluding utility or system schemas.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline input.
        Use this when you have already filtered databases and want to pass them directly for table processing.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Tables
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbTable

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Database Test1

        Return all tables in the Test1 database

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Database MyDB -Table MyTable

        Return only information on the table MyTable from the database MyDB

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Database MyDB -Table MyTable -Schema MySchema

        Return only information on the table MyTable from the database MyDB and only from the schema MySchema

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Table MyTable

        Returns information on table called MyTable if it exists in any database on the server, under any schema

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Table dbo.[First.Table]

        Returns information on table called First.Table on schema dbo if it exists in any database on the server

    .EXAMPLE
        PS C:\> 'localhost','localhost\namedinstance' | Get-DbaDbTable -Database DBA -Table Commandlog

        Returns information on the CommandLog table in the DBA database on both instances localhost and the named instance localhost\namedinstance

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Table "[[DbName]]].[Schema.With.Dots].[`"[Process]]`"]" -Verbose

        Return table information for instance Dev01 and table Process with special characters in the schema name
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$IncludeSystemDBs,
        [Alias("Name")]
        [string[]]$Table,
        [string[]]$Schema,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Table) {
            $fqTns = @()
            foreach ($t in $Table) {
                $fqTn = Get-ObjectNameParts -ObjectName $t

                if (-not $fqTn.Parsed) {
                    Write-Message -Level Warning -Message "Please check you are using proper three-part names. If your search value contains special characters you must use [ ] to wrap the name. The value $t could not be parsed as a valid name."
                    Continue
                }

                $fqTns += [PSCustomObject] @{
                    Database   = $fqTn.Database
                    Schema     = $fqTn.Schema
                    Table      = $fqTn.Name
                    InputValue = $fqTn.InputValue
                }
            }
            if (!$fqTns) {
                Stop-Function -Message "No Valid Table specified"
                return
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase | Where-Object IsAccessible
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            Write-Message -Level Verbose -Message "Processing $db"

            # Let the SMO read all properties referenced in this command for all tables in the database in one query.
            # Downside: If some other properties were already read outside of this command in the used SMO, they are cleared.
            $db.Tables.ClearAndInitialize('', [string[]]('Schema', 'Name', 'IndexSpaceUsed', 'DataSpaceUsed', 'RowCount', 'HasClusteredIndex', 'IsFileTable', 'IsMemoryOptimized', 'IsPartitioned', 'FullTextIndex', 'ChangeTrackingEnabled'))

            if ($fqTns) {
                $tables = @()
                foreach ($fqTn in $fqTns) {
                    # If the user specified a database in a three-part name, and it's not the
                    # database currently being processed, skip this table.
                    if ($fqTn.Database) {
                        if ($fqTn.Database -ne $db.Name) {
                            continue
                        }
                    }

                    $tbl = $db.tables | Where-Object { $_.Name -in $fqTn.Table -and $fqTn.Schema -in ($_.Schema, $null) -and $fqTn.Database -in ($_.Parent.Name, $null) }

                    if (-not $tbl) {
                        Write-Message -Level Verbose -Message "Could not find table $($fqTn.Table) in $db on $server"
                    }
                    $tables += $tbl
                }
            } else {
                $tables = $db.Tables
            }

            if ($Schema) {
                $tables = $tables | Where-Object Schema -in $Schema
            }

            foreach ($sqlTable in $tables) {
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name Database -Value $db.Name

                $defaultProps = "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "IndexSpaceUsed", "DataSpaceUsed", "RowCount", "HasClusteredIndex", "IsFileTable", "IsMemoryOptimized", "IsPartitioned", "FullTextIndex", "ChangeTrackingEnabled"

                Select-DefaultView -InputObject $sqlTable -Property $defaultProps
            }
        }
    }
}