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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Table

        Returns one Table object per table found in the specified databases. Each object is enhanced with dbatools-specific properties for server connection context.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name containing the table
        - Schema: The schema name that contains the table
        - Name: The table name
        - IndexSpaceUsed: Total space used by indexes for the table (in KB)
        - DataSpaceUsed: Space used by data for the table (in KB)
        - RowCount: Number of rows in the table
        - HasClusteredIndex: Boolean indicating if table has a clustered index

        Version-specific properties (included in output when available):
        - IsPartitioned: Boolean indicating if table is partitioned (SQL Server 2005+)
        - ChangeTrackingEnabled: Boolean indicating if change tracking is enabled (SQL Server 2008+)
        - IsFileTable: Boolean indicating if table is a FileTable (SQL Server 2012+)
        - IsMemoryOptimized: Boolean indicating if table is memory-optimized (SQL Server 2014+)
        - IsNode: Boolean indicating if table is a node table for graph database (SQL Server 2017+)
        - IsEdge: Boolean indicating if table is an edge table for graph database (SQL Server 2017+)

        Additional properties available from the SMO Table object:
        - FullTextIndex: FullTextIndex object for accessing full-text search configuration (if configured)
        - CreateDate: DateTime when the table was created
        - DateLastModified: DateTime when the table was last modified
        - IsSystemObject: Boolean indicating if this is a system table
        - FileStreamPartitionColumn: Name of the column used for FileStream partitioning
        - AnsiNullsStatus: Boolean indicating ANSI NULLs setting
        - QuotedIdentifierStatus: Boolean indicating QUOTED_IDENTIFIER setting

        All properties from the base SMO Table object are accessible via Select-Object *.

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
            # Build property list based on SQL Server version
            # Note: FullTextIndex is a complex object (not a scalar property) and cannot be initialized via ClearAndInitialize
            $properties = [System.Collections.ArrayList]@('Schema', 'Name', 'RowCount', 'HasClusteredIndex')

            # Azure SQL does not support IndexSpaceUsed and DataSpaceUsed via the SMO enumerator
            if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {
                $null = $properties.Add('IndexSpaceUsed')
                $null = $properties.Add('DataSpaceUsed')
            }

            # IsPartitioned available in SQL Server 2005+ (VersionMajor 9+)
            if ($server.VersionMajor -ge 9) {
                $null = $properties.Add('IsPartitioned')
            }

            # ChangeTrackingEnabled introduced in SQL Server 2008 (VersionMajor 10)
            if ($server.VersionMajor -ge 10) {
                $null = $properties.Add('ChangeTrackingEnabled')
            }

            # IsFileTable introduced in SQL Server 2012 (VersionMajor 11)
            if ($server.VersionMajor -ge 11) {
                $null = $properties.Add('IsFileTable')
            }

            # IsMemoryOptimized introduced in SQL Server 2014 (VersionMajor 12)
            if ($server.VersionMajor -ge 12) {
                $null = $properties.Add('IsMemoryOptimized')
            }

            # IsNode and IsEdge introduced in SQL Server 2017 (VersionMajor 14)
            if ($server.VersionMajor -ge 14) {
                $null = $properties.Add('IsNode')
                $null = $properties.Add('IsEdge')
            }

            # Build URN filter for server-side filtering when -Table or -Schema is specified
            # and the ClearAndInitialize optimization is enabled via config.
            # This avoids loading ALL tables when only specific ones are requested
            $urnFilter = ''
            if (($fqTns -or $Schema) -and (Get-DbatoolsConfigValue -FullName 'commands.get-dbadbtable.clearandinitialize')) {
                $filterConditions = [System.Collections.ArrayList]@()

                # Add schema filter conditions from -Schema parameter
                if ($Schema) {
                    $schemaConditions = [System.Collections.ArrayList]@()
                    foreach ($s in $Schema) {
                        $null = $schemaConditions.Add("@Schema='$s'")
                    }
                    if ($schemaConditions.Count -eq 1) {
                        $null = $filterConditions.Add($schemaConditions[0])
                    } elseif ($schemaConditions.Count -gt 1) {
                        $null = $filterConditions.Add("($($schemaConditions -join ' or '))")
                    }
                }

                # Add table name filter conditions from -Table parameter
                if ($fqTns) {
                    $tableConditions = [System.Collections.ArrayList]@()
                    foreach ($fqTn in $fqTns) {
                        # Skip if database is specified and doesn't match current database
                        if ($fqTn.Database -and $fqTn.Database -ne $db.Name) {
                            continue
                        }

                        # Only add the table name filter, schema is handled above via -Schema parameter
                        # or from the parsed table name if -Schema was not specified
                        $tableParts = [System.Collections.ArrayList]@()

                        # Add schema from table name only if -Schema parameter was not specified
                        if ($fqTn.Schema -and -not $Schema) {
                            $null = $tableParts.Add("@Schema='$($fqTn.Schema)'")
                        }

                        if ($fqTn.Table) {
                            $null = $tableParts.Add("@Name='$($fqTn.Table)'")
                        }

                        if ($tableParts.Count -gt 0) {
                            if ($tableParts.Count -eq 1) {
                                $null = $tableConditions.Add($tableParts[0])
                            } else {
                                $null = $tableConditions.Add("($($tableParts -join ' and '))")
                            }
                        }
                    }

                    if ($tableConditions.Count -gt 0) {
                        if ($tableConditions.Count -eq 1) {
                            $null = $filterConditions.Add($tableConditions[0])
                        } else {
                            $null = $filterConditions.Add("($($tableConditions -join ' or '))")
                        }
                    }
                }

                if ($filterConditions.Count -gt 0) {
                    # ClearAndInitialize expects XPath-style filter WITH outer brackets
                    # e.g., "[@Schema='dispo' and @Name='t_auftraege']"
                    # See: https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.smocollectionbase.clearandinitialize
                    $urnFilter = "[$($filterConditions -join ' and ')]"
                    Write-Message -Level Verbose -Message "Using URN filter: $urnFilter"
                }
            }

            $db.Tables.ClearAndInitialize($urnFilter, [string[]]$properties)

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

                # Build default properties list based on SQL Server version
                $defaultProps = [System.Collections.ArrayList]@("ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "IndexSpaceUsed", "DataSpaceUsed", "RowCount", "HasClusteredIndex")

                # Add version-specific properties in version order
                if ($server.VersionMajor -ge 9) {
                    $null = $defaultProps.Add("IsPartitioned")
                }
                if ($server.VersionMajor -ge 10) {
                    $null = $defaultProps.Add("ChangeTrackingEnabled")
                }
                if ($server.VersionMajor -ge 11) {
                    $null = $defaultProps.Add("IsFileTable")
                }
                if ($server.VersionMajor -ge 12) {
                    $null = $defaultProps.Add("IsMemoryOptimized")
                }
                if ($server.VersionMajor -ge 14) {
                    $null = $defaultProps.Add("IsNode")
                    $null = $defaultProps.Add("IsEdge")
                }

                # FullTextIndex is a complex object but can be displayed in output (accessed on-demand)
                $null = $defaultProps.Add("FullTextIndex")

                Select-DefaultView -InputObject $sqlTable -Property $defaultProps
            }
        }
    }
}