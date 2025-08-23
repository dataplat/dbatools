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
        The database or databases where the table will be created

    .PARAMETER Name
        The name of the table

    .PARAMETER Schema
        The schema for the table, defaults to dbo

    .PARAMETER ColumnMap
        Hashtable for easy column creation. See Examples for details

    .PARAMETER ColumnObject
        If you want to get fancy, you can build your own column objects and pass them in

    .PARAMETER InputObject
        Allows piped input from Get-DbaDatabase

    .PARAMETER AnsiNullsStatus
        No information provided by Microsoft

    .PARAMETER ChangeTrackingEnabled
        No information provided by Microsoft

    .PARAMETER DataSourceName
        No information provided by Microsoft

    .PARAMETER Durability
        No information provided by Microsoft

    .PARAMETER ExternalTableDistribution
        No information provided by Microsoft

    .PARAMETER FileFormatName
        No information provided by Microsoft

    .PARAMETER FileGroup
        No information provided by Microsoft

    .PARAMETER FileStreamFileGroup
        No information provided by Microsoft

    .PARAMETER FileStreamPartitionScheme
        No information provided by Microsoft

    .PARAMETER FileTableDirectoryName
        No information provided by Microsoft

    .PARAMETER FileTableNameColumnCollation
        No information provided by Microsoft

    .PARAMETER FileTableNamespaceEnabled
        No information provided by Microsoft

    .PARAMETER HistoryTableName
        No information provided by Microsoft

    .PARAMETER HistoryTableSchema
        No information provided by Microsoft

    .PARAMETER IsExternal
        No information provided by Microsoft

    .PARAMETER IsFileTable
        No information provided by Microsoft

    .PARAMETER IsMemoryOptimized
        No information provided by Microsoft

    .PARAMETER IsSystemVersioned
        No information provided by Microsoft

    .PARAMETER Location
        No information provided by Microsoft

    .PARAMETER LockEscalation
        No information provided by Microsoft

    .PARAMETER Owner
        No information provided by Microsoft

    .PARAMETER PartitionScheme
        No information provided by Microsoft

    .PARAMETER QuotedIdentifierStatus
        No information provided by Microsoft

    .PARAMETER RejectSampleValue
        No information provided by Microsoft

    .PARAMETER RejectType
        No information provided by Microsoft

    .PARAMETER RejectValue
        No information provided by Microsoft

    .PARAMETER RemoteDataArchiveDataMigrationState
        No information provided by Microsoft

    .PARAMETER RemoteDataArchiveEnabled
        No information provided by Microsoft

    .PARAMETER RemoteDataArchiveFilterPredicate
        No information provided by Microsoft

    .PARAMETER RemoteObjectName
        No information provided by Microsoft

    .PARAMETER RemoteSchemaName
        No information provided by Microsoft

    .PARAMETER RemoteTableName
        No information provided by Microsoft

    .PARAMETER RemoteTableProvisioned
        No information provided by Microsoft

    .PARAMETER ShardingColumnName
        No information provided by Microsoft

    .PARAMETER TextFileGroup
        No information provided by Microsoft

    .PARAMETER TrackColumnsUpdatedEnabled
        No information provided by Microsoft

    .PARAMETER HistoryRetentionPeriod
        No information provided by Microsoft

    .PARAMETER HistoryRetentionPeriodUnit
        No information provided by Microsoft

    .PARAMETER DwTableDistribution
        No information provided by Microsoft

    .PARAMETER RejectedRowLocation
        No information provided by Microsoft

    .PARAMETER OnlineHeapOperation
        No information provided by Microsoft

    .PARAMETER LowPriorityMaxDuration
        No information provided by Microsoft

    .PARAMETER DataConsistencyCheck
        No information provided by Microsoft

    .PARAMETER LowPriorityAbortAfterWait
        No information provided by Microsoft

    .PARAMETER MaximumDegreeOfParallelism
        No information provided by Microsoft

    .PARAMETER IsNode
        No information provided by Microsoft

    .PARAMETER IsEdge
        No information provided by Microsoft

    .PARAMETER IsVarDecimalStorageFormatEnabled
        No information provided by Microsoft

    .PARAMETER Passthru
        Don't create the table, just print the table script on the screen.

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
                        $object.$prop = $prop
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