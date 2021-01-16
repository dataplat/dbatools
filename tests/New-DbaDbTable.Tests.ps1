$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Name', 'Schema', 'ColumnMap', 'ColumnObject', 'AnsiNullsStatus', 'ChangeTrackingEnabled', 'DataSourceName', 'Durability', 'ExternalTableDistribution', 'FileFormatName', 'FileGroup', 'FileStreamFileGroup', 'FileStreamPartitionScheme', 'FileTableDirectoryName', 'FileTableNameColumnCollation', 'FileTableNamespaceEnabled', 'HistoryTableName', 'HistoryTableSchema', 'IsExternal', 'IsFileTable', 'IsMemoryOptimized', 'IsSystemVersioned', 'Location', 'LockEscalation', 'Owner', 'PartitionScheme', 'QuotedIdentifierStatus', 'RejectSampleValue', 'RejectType', 'RejectValue', 'RemoteDataArchiveDataMigrationState', 'RemoteDataArchiveEnabled', 'RemoteDataArchiveFilterPredicate', 'RemoteObjectName', 'RemoteSchemaName', 'RemoteTableName', 'RemoteTableProvisioned', 'ShardingColumnName', 'TextFileGroup', 'TrackColumnsUpdatedEnabled', 'HistoryRetentionPeriod', 'HistoryRetentionPeriodUnit', 'DwTableDistribution', 'RejectedRowLocation', 'OnlineHeapOperation', 'LowPriorityMaxDuration', 'DataConsistencyCheck', 'LowPriorityAbortAfterWait', 'MaximumDegreeOfParallelism', 'IsNode', 'IsEdge', 'IsVarDecimalStorageFormatEnabled', 'Passthru', 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname
        $tablename = "dbatoolssci_$(Get-Random)"
        $tablename2 = "dbatoolssci2_$(Get-Random)"
        $tablename3 = "dbatoolssci2_$(Get-Random)"
    }
    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $script:instance1 -Database $dbname -Query "drop table $tablename, $tablename2"
        $null = Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }
    Context "Should create the table" {
        BeforeEach {
            $map = @{
                Name      = 'test'
                Type      = 'varchar'
                MaxLength = 20
                Nullable  = $true
            }
        }
        It "Creates the table" {
            (New-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Name $tablename -ColumnMap $map).Name | Should -Contain $tablename
        }
        It "Really created it" {
            (Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname).Name | Should -Contain $tablename
        }
    }
    Context "Should create the table with constraint on column" {
        BeforeEach {
            $map = @{
                Name        = 'test'
                Type        = 'nvarchar'
                MaxLength   = 20
                Nullable    = $true
                Default     = 'MyTest'
                DefaultName = 'DF_MyTest'
            }
        }
        It "Creates the table" {
            (New-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Name $tablename2 -ColumnMap $map).Name | Should -Contain $tablename2
        }
        It "Has a default constraint" {
            $table = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table $tablename2
            $table.Name | Should -Contain $tablename2
            $table.Columns.DefaultConstraint.Name | Should -Contain "DF_MyTest"
        }
    }
    Context "Should create the table with an identity column" {
        BeforeEach {
            $map = @{
                Name              = 'testId'
                Type              = 'int'
                Identity          = $true
                IdentitySeed      = 10
                IdentityIncrement = 2
            }
        }
        It "Creates the table" {
            (New-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Name $tablename3 -ColumnMap $map).Name | Should -Contain $tablename3
        }
        It "Has an identity column" {
            $table = Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table $tablename3
            $table.Name | Should -Be $tablename3
            $table.Columns.Identity | Should -BeTrue
            $table.Columns.IdentitySeed | Should -Be $map.IdentitySeed
            $table.Columns.IdentityIncrement | Should -Be $map.IdentityIncrement
        }
    }
}
