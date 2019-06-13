$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Name', 'Schema', 'ColumnMap', 'ColumnObject', 'AnsiNullsStatus', 'ChangeTrackingEnabled', 'DataSourceName', 'Durability', 'ExternalTableDistribution', 'FileFormatName', 'FileGroup', 'FileStreamFileGroup', 'FileStreamPartitionScheme', 'FileTableDirectoryName', 'FileTableNameColumnCollation', 'FileTableNamespaceEnabled', 'HistoryTableName', 'HistoryTableSchema', 'IsExternal', 'IsFileTable', 'IsMemoryOptimized', 'IsSystemVersioned', 'Location', 'LockEscalation', 'Owner', 'PartitionScheme', 'QuotedIdentifierStatus', 'RejectSampleValue', 'RejectType', 'RejectValue', 'RemoteDataArchiveDataMigrationState', 'RemoteDataArchiveEnabled', 'RemoteDataArchiveFilterPredicate', 'RemoteObjectName', 'RemoteSchemaName', 'RemoteTableName', 'RemoteTableProvisioned', 'ShardingColumnName', 'TextFileGroup', 'TrackColumnsUpdatedEnabled', 'HistoryRetentionPeriod', 'HistoryRetentionPeriodUnit', 'DwTableDistribution', 'RejectedRowLocation', 'OnlineHeapOperation', 'LowPriorityMaxDuration', 'DataConsistencyCheck', 'LowPriorityAbortAfterWait', 'MaximumDegreeOfParallelism', 'IsNode', 'IsEdge', 'IsVarDecimalStorageFormatEnabled', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname
        $tablename = "dbatoolssci_$(Get-Random)"
    }
    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $script:instance1 -Database $dbname -Query "drop table $tablename"
        $null = Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }
    Context "Should create the table" {
        It "Creates the table" {
            $map = @{
                Name      = 'test'
                Type      = 'varchar'
                MaxLength = 20
                Nullable  = $true
            }
            (New-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Name $tablename -ColumnMap $map).Name | Should -Contain $tablename
        }
        It "Really created it" {
            (Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname).Name | Should -Contain $tablename
        }
    }
}