function New-DbaDbTable {
    <#
    .SYNOPSIS
        Creates a new table in a database

    .DESCRIPTION
        Creates a new table in a database

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
        PS C:\> # Create collection
        >> $cols = @()

        >> # Add columns to collection
        >> $cols += @{
        >>     Name      = 'test'
        >>     Type      = 'varchar'
        >>     MaxLength = 20
        >>     Nullable  = $true
        >> }
        PS C:\> $cols += @{
        >>     Name      = 'test2'
        >>     Type      = 'int'
        >>     Nullable  = $false
        >> }
        PS C:\> $cols += @{
        >>     Name      = 'test3'
        >>     Type      = 'decimal'
        >>     MaxLength = 9
        >>     Nullable  = $true
        >> }
        PS C:\> $cols += @{
        >>     Name      = 'test4'
        >>     Type      = 'decimal'
        >>     Precision = 8
        >>     Scale = 2
        >>     Nullable  = $false
        >> }
        PS C:\> New-DbaDbTable -SqlInstance sql2017 -Database tempdb -Name testtable -ColumnMap $cols

        Creates a new table on sql2017 in tempdb with the name testtable and four columns
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
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        function Get-SqlType {
            param([string]$TypeName)
            switch ($TypeName) {
                'Boolean' { [Data.SqlDbType]::Bit }
                'Byte[]' { [Data.SqlDbType]::VarBinary }
                'Byte' { [Data.SQLDbType]::VarBinary }
                'Datetime' { [Data.SQLDbType]::DateTime }
                'Decimal' { [Data.SqlDbType]::Decimal }
                'Double' { [Data.SqlDbType]::Float }
                'Guid' { [Data.SqlDbType]::UniqueIdentifier }
                'Int16' { [Data.SQLDbType]::SmallInt }
                'Int32' { [Data.SQLDbType]::Int }
                'Int64' { [Data.SqlDbType]::BigInt }
                'UInt16' { [Data.SQLDbType]::SmallInt }
                'UInt32' { [Data.SQLDbType]::Int }
                'UInt64' { [Data.SqlDbType]::BigInt }
                'Single' { [Data.SqlDbType]::Decimal }
                default { [Data.SqlDbType]::VarChar }
            }
        }
    }
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
            if ($Pscmdlet.ShouldProcess("Creating new object $name in $db on $server")) {
                try {
                    $object = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Table $db, $name, $schema
                    $properties = $PSBoundParameters | Where-Object Key -notin 'SqlInstance', 'SqlCredential', 'Name', 'Schema', 'ColumnMap', 'ColumnObject', 'InputObject', 'EnableException', 'Passthru'

                    foreach ($prop in $properties.Key) {
                        $object.$prop = $prop
                    }

                    foreach ($column in $ColumnObject) {
                        $object.Columns.Add($column)
                    }

                    foreach ($column in $ColumnMap) {
                        $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]$($column.Type)
                        if ($sqlDbType -eq 'VarBinary' -or $sqlDbType -eq 'VarChar') {
                            if ($column.MaxLength -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.MaxLength
                            } else {
                                $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]"$(Get-SqlType $column.DataType.Name)Max"
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                            }
                        } elseif ($sqlDbType -eq 'Decimal') {
                            if ($column.MaxLength -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.MaxLength
                            } elseif ($column.Precision -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.Precision, $column.Scale
                            } else {
                                $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]"$(Get-SqlType $column.DataType.Name)Max"
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                            }
                        } else {
                            $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                        }
                        $sqlcolumn = New-Object Microsoft.SqlServer.Management.Smo.Column $object, $column.Name, $dataType
                        $sqlcolumn.Nullable = $column.Nullable
                        $object.Columns.Add($sqlcolumn)
                    }

                    if ($Passthru) {
                        $object.Script()
                    } else {
                        $null = Invoke-Create -Object $object
                    }
                    $db | Get-DbaDbTable -Table $Name
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}