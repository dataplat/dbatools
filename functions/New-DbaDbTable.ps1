function Get-Table {
    <#
    .SYNOPSIS


    .DESCRIPTION


   .PARAMETER SqlInstance
       The target SQL Server instance or instances.

    .PARAMETER SqlCredential
       Login to the SqlInstance instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Name


    .PARAMETER Schema

    .PARAMETER InputObject


    .PARAMETER AnsiNullsStatus


    .PARAMETER ChangeTrackingEnabled


    .PARAMETER DataSourceName


    .PARAMETER Durability


    .PARAMETER ExternalTableDistribution


    .PARAMETER FileFormatName


    .PARAMETER FileGroup


    .PARAMETER FileStreamFileGroup


    .PARAMETER FileStreamPartitionScheme


    .PARAMETER FileTableDirectoryName


    .PARAMETER FileTableNameColumnCollation


    .PARAMETER FileTableNamespaceEnabled


    .PARAMETER HistoryTableName


    .PARAMETER HistoryTableSchema


    .PARAMETER IsExternal


    .PARAMETER IsFileTable


    .PARAMETER IsMemoryOptimized


    .PARAMETER IsSystemVersioned


    .PARAMETER Location


    .PARAMETER LockEscalation


    .PARAMETER Owner


    .PARAMETER PartitionScheme


    .PARAMETER QuotedIdentifierStatus


    .PARAMETER RejectSampleValue


    .PARAMETER RejectType


    .PARAMETER RejectValue


    .PARAMETER RemoteDataArchiveDataMigrationState


    .PARAMETER RemoteDataArchiveEnabled


    .PARAMETER RemoteDataArchiveFilterPredicate


    .PARAMETER RemoteObjectName


    .PARAMETER RemoteSchemaName


    .PARAMETER RemoteTableName


    .PARAMETER RemoteTableProvisioned


    .PARAMETER ShardingColumnName


    .PARAMETER TextFileGroup


    .PARAMETER TrackColumnsUpdatedEnabled


    .PARAMETER HistoryRetentionPeriod


    .PARAMETER HistoryRetentionPeriodUnit


    .PARAMETER DwTableDistribution


    .PARAMETER RejectedRowLocation


    .PARAMETER OnlineHeapOperation


    .PARAMETER LowPriorityMaxDuration


    .PARAMETER DataConsistencyCheck


    .PARAMETER LowPriorityAbortAfterWait


    .PARAMETER MaximumDegreeOfParallelism


    .PARAMETER IsNode


    .PARAMETER IsEdge


    .PARAMETER IsVarDecimalStorageFormatEnabled


    .PARAMETER WhatIf
       Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
       Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
       By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
       This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
       Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
       Tags:
       Author:
       Website: https://dbatools.io
       Copyright: (c) 2018 by dbatools, licensed under MIT
       License: MIT https://opensource.org/licenses/MIT

    .LINK
       https://dbatools.io/Get-Table

    .EXAMPLE
       PS C:\> Get-Table -SqlInstance sql2017a -Confirm

       Prompts for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [String]$Name,
        [String]$Schema = "dbo",
        [hashtable]$ColumnMap,
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
                'Boolean' {[Data.SqlDbType]::Bit}
                'Byte[]' {[Data.SqlDbType]::VarBinary}
                'Byte' {[Data.SQLDbType]::VarBinary}
                'Datetime' {[Data.SQLDbType]::DateTime}
                'Decimal' {[Data.SqlDbType]::Decimal}
                'Double' {[Data.SqlDbType]::Float}
                'Guid' {[Data.SqlDbType]::UniqueIdentifier}
                'Int16' {[Data.SQLDbType]::SmallInt}
                'Int32' {[Data.SQLDbType]::Int}
                'Int64' {[Data.SqlDbType]::BigInt}
                'UInt16' {[Data.SQLDbType]::SmallInt}
                'UInt32' {[Data.SQLDbType]::Int}
                'UInt64' {[Data.SqlDbType]::BigInt}
                'Single' {[Data.SqlDbType]::Decimal}
                default {[Data.SqlDbType]::VarChar}
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

        foreach ($item in $InputObject) {
            if ($Pscmdlet.ShouldProcess("Creating new object Microsoft.SqlServer.Management.Smo.Table")) {
                try {
                    $object = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Table $item, $name, $schema
                    $object.AnsiNullsStatus = $AnsiNullsStatus
                    $object.ChangeTrackingEnabled = $ChangeTrackingEnabled
                    $object.DataSourceName = $DataSourceName
                    $object.Durability = $Durability
                    $object.ExternalTableDistribution = $ExternalTableDistribution
                    $object.FileFormatName = $FileFormatName
                    $object.FileGroup = $FileGroup
                    $object.FileStreamFileGroup = $FileStreamFileGroup
                    $object.FileStreamPartitionScheme = $FileStreamPartitionScheme
                    $object.FileTableDirectoryName = $FileTableDirectoryName
                    $object.FileTableNameColumnCollation = $FileTableNameColumnCollation
                    $object.FileTableNamespaceEnabled = $FileTableNamespaceEnabled
                    $object.HistoryTableName = $HistoryTableName
                    $object.HistoryTableSchema = $HistoryTableSchema
                    $object.IsExternal = $IsExternal
                    $object.IsFileTable = $IsFileTable
                    $object.IsMemoryOptimized = $IsMemoryOptimized
                    $object.IsSystemVersioned = $IsSystemVersioned
                    $object.Location = $Location
                    $object.LockEscalation = $LockEscalation
                    $object.Owner = $Owner
                    $object.PartitionScheme = $PartitionScheme
                    $object.QuotedIdentifierStatus = $QuotedIdentifierStatus
                    $object.RejectSampleValue = $RejectSampleValue
                    $object.RejectType = $RejectType
                    $object.RejectValue = $RejectValue
                    $object.RemoteDataArchiveDataMigrationState = $RemoteDataArchiveDataMigrationState
                    $object.RemoteDataArchiveEnabled = $RemoteDataArchiveEnabled
                    $object.RemoteDataArchiveFilterPredicate = $RemoteDataArchiveFilterPredicate
                    $object.RemoteObjectName = $RemoteObjectName
                    $object.RemoteSchemaName = $RemoteSchemaName
                    $object.RemoteTableName = $RemoteTableName
                    $object.RemoteTableProvisioned = $RemoteTableProvisioned
                    $object.ShardingColumnName = $ShardingColumnName
                    $object.TextFileGroup = $TextFileGroup
                    $object.TrackColumnsUpdatedEnabled = $TrackColumnsUpdatedEnabled
                    $object.HistoryRetentionPeriod = $HistoryRetentionPeriod
                    $object.HistoryRetentionPeriodUnit = $HistoryRetentionPeriodUnit
                    $object.DwTableDistribution = $DwTableDistribution
                    $object.RejectedRowLocation = $RejectedRowLocation
                    $object.OnlineHeapOperation = $OnlineHeapOperation
                    $object.LowPriorityMaxDuration = $LowPriorityMaxDuration
                    $object.DataConsistencyCheck = $DataConsistencyCheck
                    $object.LowPriorityAbortAfterWait = $LowPriorityAbortAfterWait
                    $object.MaximumDegreeOfParallelism = $MaximumDegreeOfParallelism
                    $object.IsNode = $IsNode
                    $object.IsEdge = $IsEdge
                    $object.IsVarDecimalStorageFormatEnabled = $IsVarDecimalStorageFormatEnabled

                    foreach ($column in $ColumnMap) {
                        $ColumnMap = @{
                            Name      = 'test'
                            Type      = 'varchar'
                            MaxLength = 20
                            Nullable  = $true
                        }
                        $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]$($column.Type)
                        if ($sqlDbType -eq 'VarBinary' -or $sqlDbType -eq 'VarChar') {
                            if ($column.MaxLength -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $maxlength
                            } else {
                                $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]"$(Get-SqlType $column.DataType.Name)Max"
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                            }
                        } else {
                            $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                        }
                        $sqlcolumn = New-Object Microsoft.SqlServer.Management.Smo.Column $table, $column.Name, $dataType
                        $sqlcolumn.Nullable = $column.Nullable
                        $object.Columns.Add($sqlcolumn)
                    }

                    if ($Passthru) {
                        $object.Script()
                    } else {
                        Invoke-Create -Object $object
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}