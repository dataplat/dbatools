function New-DbaDbTable {
    <#
    .SYNOPSIS
        Creates database tables with columns and constraints using PowerShell hashtables or SMO objects

    .DESCRIPTION
        Creates new tables in SQL Server databases with specified columns, data types, constraints, and properties. You can define table structure using simple PowerShell hashtables for columns or pass in pre-built SMO column objects for advanced scenarios. The function handles all common column properties including data types, nullability, default values, identity columns, and decimal precision/scale. It also supports advanced table features like memory optimization, temporal tables, file tables, and external tables. If the specified schema doesn't exist, it will be created automatically.

   .PARAMETER SqlInstance
       The target SQL Server instance or instances.

    .PARAMETER SqlCredential
       Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database where the new table will be created. Accepts multiple database names to create the same table across several databases.
        Use this when you need to deploy identical table structures to multiple databases in your environment.

    .PARAMETER Name
        Specifies the name for the new table. Must be a valid SQL Server identifier.
        Use standard naming conventions like avoiding spaces and reserved keywords for better maintainability.

    .PARAMETER Schema
        Specifies the schema where the table will be created. Defaults to 'dbo' if not specified.
        Use this to organize tables by functional area or security requirements. The schema will be created automatically if it doesn't exist.

    .PARAMETER ColumnMap
        Defines table columns using PowerShell hashtables with properties like Name, Type, MaxLength, Nullable, Default, Identity, etc.
        This is the primary method for specifying column structure when you need simple, declarative table creation. See examples for supported hashtable properties.

    .PARAMETER ColumnObject
        Accepts pre-built SMO Column objects for advanced scenarios requiring complex column configurations.
        Use this when you need features not supported by ColumnMap hashtables, such as computed columns or advanced constraints.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase for creating tables across multiple databases.
        Use this in pipeline scenarios where you want to apply table creation to a filtered set of databases.

    .PARAMETER AnsiNullsStatus
        Controls ANSI_NULLS setting for the table, affecting how null comparisons are handled in queries.
        Enable this to ensure ANSI-compliant null handling behavior, which is recommended for modern applications.

    .PARAMETER ChangeTrackingEnabled
        Enables SQL Server Change Tracking on the table to monitor data modifications.
        Use this when you need to track which rows have been inserted, updated, or deleted for synchronization scenarios.

    .PARAMETER DataSourceName
        Specifies the external data source name for external tables in SQL Server 2016+ or Azure SQL.
        Required when creating external tables that reference data in Hadoop, Azure Blob Storage, or other external systems.

    .PARAMETER Durability
        Sets the durability level for memory-optimized tables (SCHEMA_AND_DATA or SCHEMA_ONLY).
        Use SCHEMA_ONLY for temporary data that doesn't need to persist across server restarts, or SCHEMA_AND_DATA for permanent memory-optimized tables.

    .PARAMETER ExternalTableDistribution
        Specifies the distribution method for external tables in Azure SQL Data Warehouse or Parallel Data Warehouse.
        Choose between HASH, ROUND_ROBIN, or REPLICATE based on your query patterns and data size requirements.

    .PARAMETER FileFormatName
        Specifies the external file format name for external tables that read from files.
        Required when creating external tables that reference structured files like CSV, Parquet, or ORC in external storage systems.

    .PARAMETER FileGroup
        Specifies the filegroup where the table data will be stored. Defaults to the database's default filegroup.
        Use this to control storage placement for performance optimization or to separate tables across different storage devices.

    .PARAMETER FileStreamFileGroup
        Specifies the FILESTREAM filegroup for tables that store large binary data as files.
        Required when creating tables with FILESTREAM columns for storing documents, images, or other large binary objects.

    .PARAMETER FileStreamPartitionScheme
        Specifies the partition scheme for FILESTREAM data in partitioned tables.
        Use this when you need to partition FILESTREAM data across multiple filegroups for performance or maintenance benefits.

    .PARAMETER FileTableDirectoryName
        Sets the directory name for FileTable functionality, allowing Windows file system access to table data.
        Specify a meaningful name that will appear as a folder in the Windows file system when accessing the table through the file share.

    .PARAMETER FileTableNameColumnCollation
        Specifies the collation for the name column in FileTable to control file name sorting and comparison.
        Use a case-insensitive collation for Windows-compatible file name handling in FileTable scenarios.

    .PARAMETER FileTableNamespaceEnabled
        Enables the FileTable namespace, allowing file system access through Windows APIs.
        Set to true when you want applications to access table data through standard file operations like copy, move, and delete.

    .PARAMETER HistoryTableName
        Specifies the name of the history table for system-versioned temporal tables.
        Required when creating temporal tables that automatically track all data changes for point-in-time queries and auditing.

    .PARAMETER HistoryTableSchema
        Specifies the schema for the history table in system-versioned temporal tables.
        Use this to organize history tables in a separate schema for better security and maintenance separation from current data.

    .PARAMETER IsExternal
        Creates an external table that references data stored outside SQL Server.
        Use this for querying data in Azure Blob Storage, Hadoop, or other external systems without importing the data into SQL Server.

    .PARAMETER IsFileTable
        Creates a FileTable that combines relational data with Windows file system access.
        Enable this when you need applications to store and manage documents through both T-SQL and standard Windows file operations.

    .PARAMETER IsMemoryOptimized
        Creates an In-Memory OLTP table stored entirely in memory for high-performance scenarios.
        Use this for tables requiring extremely high transaction throughput with low latency, typically in OLTP workloads.

    .PARAMETER IsSystemVersioned
        Creates a temporal table that automatically tracks all data changes with system-generated timestamps.
        Enable this for auditing requirements or when you need to query historical versions of data at any point in time.

    .PARAMETER Location
        Specifies the location path for external tables pointing to files or directories.
        Required for external tables to define where the actual data files are stored in the external system.

    .PARAMETER LockEscalation
        Controls when SQL Server escalates row or page locks to table locks (TABLE, AUTO, or DISABLE).
        Set to DISABLE for high-concurrency scenarios where table-level locks would cause blocking, or AUTO for default behavior.

    .PARAMETER Owner
        Specifies the table owner, typically a database user or role with appropriate permissions.
        Use this to set explicit ownership for security or administrative purposes, though schema-contained objects are generally preferred.

    .PARAMETER PartitionScheme
        Specifies the partition scheme for horizontally partitioning large tables across multiple filegroups.
        Use this for very large tables to improve query performance and enable parallel maintenance operations on partition boundaries.

    .PARAMETER QuotedIdentifierStatus
        Controls QUOTED_IDENTIFIER setting for the table, affecting how double quotes are interpreted in queries.
        Enable this to use double quotes for identifiers containing spaces or reserved words, following ANSI SQL standards.

    .PARAMETER RejectSampleValue
        Sets the sample size for reject value calculations in external tables with error handling.
        Specify the number of rows to sample when determining if reject thresholds have been exceeded during external data access.

    .PARAMETER RejectType
        Defines how reject values are calculated for external tables (VALUE or PERCENTAGE).
        Use VALUE for absolute row count limits or PERCENTAGE for proportional error thresholds when accessing external data sources.

    .PARAMETER RejectValue
        Sets the maximum number or percentage of rejected rows allowed when querying external tables.
        Configure this to control query behavior when encountering data quality issues in external data sources.

    .PARAMETER RemoteDataArchiveDataMigrationState
        Controls the data migration state for Stretch Database tables (INBOUND, OUTBOUND, or PAUSED).
        Use this to manage how historical data is migrated between on-premises SQL Server and Azure SQL Database.

    .PARAMETER RemoteDataArchiveEnabled
        Enables Stretch Database functionality to automatically migrate cold data to Azure SQL Database.
        Use this for tables with historical data that can be moved to lower-cost cloud storage while remaining queryable.

    .PARAMETER RemoteDataArchiveFilterPredicate
        Defines the filter function determining which rows are eligible for Stretch Database migration.
        Specify a function that returns 1 for rows to migrate, typically based on date criteria for archiving old data.

    .PARAMETER RemoteObjectName
        Specifies the name of the remote table or object for Stretch Database or external table scenarios.
        Use this when the remote table name differs from the local table name in federated or hybrid configurations.

    .PARAMETER RemoteSchemaName
        Specifies the schema name in the remote database for Stretch Database tables.
        Define this when the remote Azure SQL Database uses a different schema structure than your local database.

    .PARAMETER RemoteTableName
        Sets the table name in the remote Azure SQL Database for Stretch Database functionality.
        Specify this when you want the archived data to use a different table name in the cloud storage location.

    .PARAMETER RemoteTableProvisioned
        Indicates whether the remote table for Stretch Database has already been created in Azure SQL Database.
        Set to true if the remote table structure already exists, preventing automatic provisioning during setup.

    .PARAMETER ShardingColumnName
        Specifies the column used for sharding data distribution in Azure SQL Database elastic pools.
        Define the column that determines how rows are distributed across multiple database shards for horizontal scaling.

    .PARAMETER TextFileGroup
        Specifies the filegroup for storing text, ntext, and image columns in SQL Server versions before 2016.
        Use this for legacy applications requiring separate storage for large text data, though newer data types are recommended.

    .PARAMETER TrackColumnsUpdatedEnabled
        Enables column-level change tracking to identify which specific columns were modified.
        Use this when you need granular change information beyond just knowing that a row was updated, useful for selective synchronization.

    .PARAMETER HistoryRetentionPeriod
        Sets the retention period for temporal table history data before automatic cleanup.
        Specify the number of time units (days, months, years) to retain historical data for compliance and storage management.

    .PARAMETER HistoryRetentionPeriodUnit
        Defines the time unit for history retention period (DAYS, WEEKS, MONTHS, or YEARS).
        Use this with HistoryRetentionPeriod to control how long temporal table history is preserved before automatic deletion.

    .PARAMETER DwTableDistribution
        Specifies the distribution strategy for data warehouse tables (HASH, ROUND_ROBIN, or REPLICATE).
        Choose HASH for large fact tables, ROUND_ROBIN for staging tables, or REPLICATE for small dimension tables in analytical workloads.

    .PARAMETER RejectedRowLocation
        Specifies where to store rows that exceed reject thresholds when querying external tables.
        Define a location for storing problematic rows for later analysis and data quality troubleshooting.

    .PARAMETER OnlineHeapOperation
        Enables online operations for heap tables during index creation or rebuilding.
        Use this to minimize blocking and maintain table availability during maintenance operations on tables without clustered indexes.

    .PARAMETER LowPriorityMaxDuration
        Sets the maximum time in minutes for low-priority lock waits during online operations.
        Specify how long online operations should wait for locks before taking alternative action to balance performance and availability.

    .PARAMETER DataConsistencyCheck
        Enables data consistency validation during online index operations.
        Use this to ensure data integrity is maintained during concurrent modifications to tables undergoing maintenance operations.

    .PARAMETER LowPriorityAbortAfterWait
        Defines the action to take when low-priority operations exceed their maximum wait duration.
        Choose how to handle lock conflicts: continue waiting, abort the operation, or kill blocking transactions.

    .PARAMETER MaximumDegreeOfParallelism
        Limits the number of processors used during table operations like index creation.
        Set this to control resource usage and prevent single operations from consuming all available CPU cores.

    .PARAMETER IsNode
        Creates a node table for SQL Server 2017+ Graph Database functionality.
        Enable this when building graph databases where the table will store entities and their properties for relationship modeling.

    .PARAMETER IsEdge
        Creates an edge table for SQL Server 2017+ Graph Database functionality to store relationships.
        Enable this when building graph databases where the table will store connections between node tables.

    .PARAMETER IsVarDecimalStorageFormatEnabled
        Enables variable-length decimal storage format to reduce storage space for decimal and numeric columns.
        Use this for tables with many decimal columns containing leading zeros or small values to optimize storage efficiency.

    .PARAMETER Passthru
        Returns the T-SQL script for table creation instead of executing it immediately.
        Use this to review, modify, or save table creation scripts before deployment, or to generate scripts for version control.

    .PARAMETER WhatIf
       Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
       Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
       By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
       This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
       Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
       Tags: table
       Author: Chrissy LeMaire (@cl)
       Website: https://dbatools.io
       Copyright: (c) 2019 by dbatools, licensed under MIT
       License: MIT https://opensource.org/licenses/MIT

    .LINK
       https://dbatools.io/New-DbaDbTable

    .EXAMPLE
       PS C:\> $col = @{
       >> Name      = 'test'
       >> Type      = 'varchar'
       >> MaxLength = 20
       >> Nullable  = $true
       >> }
       PS C:\> New-DbaDbTable -SqlInstance sql2017 -Database tempdb -Name testtable -ColumnMap $col

       Creates a new table on sql2017 in tempdb with the name testtable and one column

    .EXAMPLE
       PS C:\> $cols = @( )
       >> $cols += @{
       >>     Name              = 'Id'
       >>     Type              = 'varchar'
       >>     MaxLength         = 36
       >>     DefaultExpression = 'NEWID()'
       >> }
       >> $cols += @{
       >>     Name          = 'Since'
       >>     Type          = 'datetime2'
       >>     DefaultString = '2021-12-31'
       >> }
       PS C:\> New-DbaDbTable -SqlInstance sql2017 -Database tempdb -Name testtable -ColumnMap $cols

       Creates a new table on sql2017 in tempdb with the name testtable and two columns.
       Uses "DefaultExpression" to interpret the value "NEWID()" as an expression regardless of the data type of the column.
       Uses "DefaultString" to interpret the value "2021-12-31" as a string regardless of the data type of the column.

    .EXAMPLE
        PS C:\> # Create collection
        >> $cols = @()

        >> # Add columns to collection
        >> $cols += @{
        >>     Name      = 'testId'
        >>     Type      = 'int'
        >>     Identity  = $true
        >> }
        >> $cols += @{
        >>     Name      = 'test'
        >>     Type      = 'varchar'
        >>     MaxLength = 20
        >>     Nullable  = $true
        >> }
        >> $cols += @{
        >>     Name      = 'test2'
        >>     Type      = 'int'
        >>     Nullable  = $false
        >> }
        >> $cols += @{
        >>     Name      = 'test3'
        >>     Type      = 'decimal'
        >>     MaxLength = 9
        >>     Nullable  = $true
        >> }
        >> $cols += @{
        >>     Name      = 'test4'
        >>     Type      = 'decimal'
        >>     Precision = 8
        >>     Scale = 2
        >>     Nullable  = $false
        >> }
        >> $cols += @{
        >>     Name      = 'test5'
        >>     Type      = 'Nvarchar'
        >>     MaxLength = 50
        >>     Nullable  =  $false
        >>     Default  =  'Hello'
        >>     DefaultName = 'DF_Name_test5'
        >> }
        >> $cols += @{
        >>     Name      = 'test6'
        >>     Type      = 'int'
        >>     Nullable  =  $false
        >>     Default  =  '0'
        >> }
        >> $cols += @{
        >>     Name      = 'test7'
        >>     Type      = 'smallint'
        >>     Nullable  =  $false
        >>     Default  =  100
        >> }
        >> $cols += @{
        >>     Name      = 'test8'
        >>     Type      = 'Nchar'
        >>     MaxLength = 3
        >>     Nullable  =  $false
        >>     Default  =  'ABC'
        >> }
        >> $cols += @{
        >>     Name      = 'test9'
        >>     Type      = 'char'
        >>     MaxLength = 4
        >>     Nullable  =  $false
        >>     Default  =  'XPTO'
        >> }
        >> $cols += @{
        >>     Name      = 'test10'
        >>     Type      = 'datetime'
        >>     Nullable  =  $false
        >>     Default  =  'GETDATE()'
        >> }

        PS C:\> New-DbaDbTable -SqlInstance sql2017 -Database tempdb -Name testtable -ColumnMap $cols

        Creates a new table on sql2017 in tempdb with the name testtable and ten columns.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [String[]]$Database,
        [Alias("Table")]
        [String]$Name,
        [String]$Schema = "dbo",
        [hashtable[]]$ColumnMap,
        [Microsoft.SqlServer.Management.Smo.Column[]]$ColumnObject,
        [Switch]$AnsiNullsStatus,
        [Switch]$ChangeTrackingEnabled,
        [String]$DataSourceName,
        [Microsoft.SqlServer.Management.Smo.DurabilityType]$Durability,
        [Microsoft.SqlServer.Management.Smo.ExternalTableDistributionType]$ExternalTableDistribution,
        [String]$FileFormatName,
        [String]$FileGroup,
        [String]$FileStreamFileGroup,
        [String]$FileStreamPartitionScheme,
        [String]$FileTableDirectoryName,
        [String]$FileTableNameColumnCollation,
        [Switch]$FileTableNamespaceEnabled,
        [String]$HistoryTableName,
        [String]$HistoryTableSchema,
        [Switch]$IsExternal,
        [Switch]$IsFileTable,
        [Switch]$IsMemoryOptimized,
        [Switch]$IsSystemVersioned,
        [String]$Location,
        [Microsoft.SqlServer.Management.Smo.LockEscalationType]$LockEscalation,
        [String]$Owner,
        [String]$PartitionScheme,
        [Switch]$QuotedIdentifierStatus,
        [Double]$RejectSampleValue,
        [Microsoft.SqlServer.Management.Smo.ExternalTableRejectType]$RejectType,
        [Double]$RejectValue,
        [Microsoft.SqlServer.Management.Smo.RemoteDataArchiveMigrationState]$RemoteDataArchiveDataMigrationState,
        [Switch]$RemoteDataArchiveEnabled,
        [String]$RemoteDataArchiveFilterPredicate,
        [String]$RemoteObjectName,
        [String]$RemoteSchemaName,
        [String]$RemoteTableName,
        [Switch]$RemoteTableProvisioned,
        [String]$ShardingColumnName,
        [String]$TextFileGroup,
        [Switch]$TrackColumnsUpdatedEnabled,
        [Int32]$HistoryRetentionPeriod,
        [Microsoft.SqlServer.Management.Smo.TemporalHistoryRetentionPeriodUnit]$HistoryRetentionPeriodUnit,
        [Microsoft.SqlServer.Management.Smo.DwTableDistributionType]$DwTableDistribution,
        [String]$RejectedRowLocation,
        [Switch]$OnlineHeapOperation,
        [Int32]$LowPriorityMaxDuration,
        [Switch]$DataConsistencyCheck,
        [Microsoft.SqlServer.Management.Smo.AbortAfterWait]$LowPriorityAbortAfterWait,
        [Int32]$MaximumDegreeOfParallelism,
        [Switch]$IsNode,
        [Switch]$IsEdge,
        [Switch]$IsVarDecimalStorageFormatEnabled,
        [switch]$Passthru,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance)) {
            if ((Test-Bound -Not -ParameterName Database) -or (Test-Bound -Not -ParameterName Name)) {
                Stop-Function -Message "You must specify one or more databases and one Name when using the SqlInstance parameter."
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            if ($Pscmdlet.ShouldProcess("Creating new table [$Schema].[$Name] in $db on $server")) {
                # Test if table already exists. This ways we can drop the table if part of the creation fails.
                $existingTable = $db.tables | Where-Object { $_.Schema -eq $Schema -and $_.Name -eq $Name }
                if ($existingTable) {
                    Stop-Function -Message "Table [$Schema].[$Name] already exists in $db on $server" -Continue
                }
                try {
                    $object = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Table $db, $Name, $Schema
                    $properties = $PSBoundParameters | Where-Object Key -notin 'SqlInstance', 'SqlCredential', 'Name', 'Schema', 'ColumnMap', 'ColumnObject', 'InputObject', 'EnableException', 'Passthru'

                    foreach ($prop in $properties.Key) {
                        $object.$prop = $properties[$prop]
                    }

                    foreach ($column in $ColumnObject) {
                        $object.Columns.Add($column)
                    }

                    foreach ($column in $ColumnMap) {
                        $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]$($column.Type)
                        if ($sqlDbType -in @('VarBinary', 'VarChar', 'NVarChar', 'Char', 'NChar')) {
                            if ($column.MaxLength -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.MaxLength
                            } else {
                                $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]"$($column.Type)Max"
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                            }
                        } elseif ($sqlDbType -eq 'Decimal') {
                            if ($column.MaxLength -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.MaxLength
                            } elseif ($column.Precision -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.Precision, $column.Scale
                            } else {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                            }
                        } else {
                            $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                        }
                        $sqlColumn = New-Object Microsoft.SqlServer.Management.Smo.Column $object, $column.Name, $dataType
                        $sqlColumn.Nullable = $column.Nullable

                        if ($column.DefaultName) {
                            $dfName = $column.DefaultName
                        } else {
                            $dfName = "DF_$name`_$($column.Name)"
                        }
                        if ($column.DefaultExpression) {
                            # override the default that would add quotes to an expression
                            $sqlColumn.AddDefaultConstraint($dfName).Text = $column.DefaultExpression
                        } elseif ($column.DefaultString) {
                            # override the default that would not add quotes to a date string
                            $sqlColumn.AddDefaultConstraint($dfName).Text = "'$($column.DefaultString)'"
                        } elseif ($column.Default) {
                            if ($sqlDbType -in @('NVarchar', 'NChar', 'NVarcharMax', 'NCharMax')) {
                                $sqlColumn.AddDefaultConstraint($dfName).Text = "N'$($column.Default)'"
                            } elseif ($sqlDbType -in @('Varchar', 'Char', 'VarcharMax', 'CharMax')) {
                                $sqlColumn.AddDefaultConstraint($dfName).Text = "'$($column.Default)'"
                            } else {
                                $sqlColumn.AddDefaultConstraint($dfName).Text = $column.Default
                            }
                        }

                        if ($column.Identity) {
                            $sqlColumn.Identity = $true
                            if ($column.IdentitySeed) {
                                $sqlColumn.IdentitySeed = $column.IdentitySeed
                            }
                            if ($column.IdentityIncrement) {
                                $sqlColumn.IdentityIncrement = $column.IdentityIncrement
                            }
                        }
                        $object.Columns.Add($sqlColumn)
                    }

                    # user has specified a schema that does not exist yet
                    $schemaObject = $null
                    if (-not ($db | Get-DbaDbSchema -Schema $Schema -IncludeSystemSchemas)) {
                        Write-Message -Level Verbose -Message "Schema $Schema does not exist in $db and will be created."
                        $schemaObject = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Schema $db, $Schema
                    }

                    if ($Passthru) {
                        $ScriptingOptionsObject = New-DbaScriptingOption
                        $ScriptingOptionsObject.ContinueScriptingOnError = $false
                        $ScriptingOptionsObject.DriAllConstraints = $true

                        if ($schemaObject) {
                            $schemaObject.Script($ScriptingOptionsObject)
                        }

                        $object.Script($ScriptingOptionsObject)
                    } else {
                        if ($schemaObject) {
                            $null = Invoke-Create -Object $schemaObject
                        }
                        $null = Invoke-Create -Object $object
                    }
                    $db | Get-DbaDbTable -Table "[$Schema].[$Name]"
                } catch {
                    $exception = $_
                    Write-Message -Level Verbose -Message "Failed to create table or failure while adding constraints. Will try to remove table (and schema)."
                    try {
                        $object.Refresh()
                        $object.DropIfExists()
                        if ($schemaObject) {
                            $schemaObject.Refresh()
                            $schemaObject.DropIfExists()
                        }
                    } catch {
                        Write-Message -Level Warning -Message "Failed to drop table: $_. Maybe table still exists."
                    }
                    Stop-Function -Message "Failure" -ErrorRecord $exception -Continue
                }
            }
        }
    }
}