#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbTable",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Name",
                "Schema",
                "ColumnMap",
                "ColumnObject",
                "AnsiNullsStatus",
                "ChangeTrackingEnabled",
                "DataSourceName",
                "Durability",
                "ExternalTableDistribution",
                "FileFormatName",
                "FileGroup",
                "FileStreamFileGroup",
                "FileStreamPartitionScheme",
                "FileTableDirectoryName",
                "FileTableNameColumnCollation",
                "FileTableNamespaceEnabled",
                "HistoryTableName",
                "HistoryTableSchema",
                "IsExternal",
                "IsFileTable",
                "IsMemoryOptimized",
                "IsSystemVersioned",
                "Location",
                "LockEscalation",
                "Owner",
                "PartitionScheme",
                "QuotedIdentifierStatus",
                "RejectSampleValue",
                "RejectType",
                "RejectValue",
                "RemoteDataArchiveDataMigrationState",
                "RemoteDataArchiveEnabled",
                "RemoteDataArchiveFilterPredicate",
                "RemoteObjectName",
                "RemoteSchemaName",
                "RemoteTableName",
                "RemoteTableProvisioned",
                "ShardingColumnName",
                "TextFileGroup",
                "TrackColumnsUpdatedEnabled",
                "HistoryRetentionPeriod",
                "HistoryRetentionPeriodUnit",
                "DwTableDistribution",
                "RejectedRowLocation",
                "OnlineHeapOperation",
                "LowPriorityMaxDuration",
                "DataConsistencyCheck",
                "LowPriorityAbortAfterWait",
                "MaximumDegreeOfParallelism",
                "IsNode",
                "IsEdge",
                "IsVarDecimalStorageFormatEnabled",
                "Passthru",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbname = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $dbname
        $tablename = "dbatoolssci_$(Get-Random)"
        $tablename2 = "dbatoolssci2_$(Get-Random)"
        $tablename3 = "dbatoolssci2_$(Get-Random)"
        $tablename4 = "dbatoolssci2_$(Get-Random)"
        $tablename5 = "dbatoolssci2_$(Get-Random)"
        $tablenameNode = "dbatoolssci_node_$(Get-Random)"
        $tablenameEdge = "dbatoolssci_edge_$(Get-Random)"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Query "drop table $tablename, $tablename2"
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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
            (New-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Name $tablename -ColumnMap $map).Name | Should -Contain $tablename
        }
        It "Really created it" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname).Name | Should -Contain $tablename
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
            (New-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Name $tablename2 -ColumnMap $map).Name | Should -Contain $tablename2
        }
        It "Has a default constraint" {
            $table = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Table $tablename2
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
            (New-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Name $tablename3 -ColumnMap $map).Name | Should -Contain $tablename3
        }
        It "Has an identity column" {
            $table = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Table $tablename3
            $table.Name | Should -Be $tablename3
            $table.Columns.Identity | Should -BeTrue
            $table.Columns.IdentitySeed | Should -Be $map.IdentitySeed
            $table.Columns.IdentityIncrement | Should -Be $map.IdentityIncrement
        }
    }
    Context "Should create the table with using DefaultExpression and DefaultString" {
        It "Creates the table" {
            $map = @( )
            $map += @{
                Name              = 'Id'
                Type              = 'varchar'
                MaxLength         = 36
                DefaultExpression = 'NEWID()'
            }
            $map += @{
                Name          = 'Since'
                Type          = 'datetime2'
                DefaultString = '2021-12-31'
            }
            { $null = New-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Name $tablename4 -ColumnMap $map -EnableException } | Should -Not -Throw
        }
    }
    Context "Should create the table with a nvarcharmax column" {
        BeforeEach {
            $map = @{
                Name     = 'test'
                Type     = 'nvarchar'
                Nullable = $true
            }
        }
        It "Creates the table" {
            (New-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Name $tablename5 -ColumnMap $map).Name | Should -Contain $tablename5
        }
        It "Has the correct column datatype" {
            $table = Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Table $tablename5
            $table.Columns['test'].DataType.SqlDataType | Should -Be "NVarCharMax"
        }
    }
    Context "Should create the schema if it doesn't exist" {

        It "schema created" {
            $random = Get-Random
            $tableName = "table_$random"
            $schemaName = "schema_$random"
            $map = @{
                Name = "testId"
                Type = "int"
            }

            $tableWithSchema = New-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Name $tableName -ColumnMap $map -Schema $schemaName
            $tableWithSchema.Count | Should -Be 1
            $tableWithSchema.Database | Should -Be $dbname
            $tableWithSchema.Name | Should -Be "table_$random"
            $tableWithSchema.Schema | Should -Be "schema_$random"
        }

        It "schema scripted via -Passthru" {
            $random = Get-Random
            $tableName = "table2_$random"
            $schemaName = "schema2_$random"
            $map = @{
                Name = "testId"
                Type = "int"
            }

            $tableWithSchema = New-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -Name $tableName -ColumnMap $map -Schema $schemaName -Passthru
            $tableWithSchema[0] | Should -Be "CREATE SCHEMA [$schemaName]"
            $tableWithSchema[2] | Should -Match "$schemaName"
            $tableWithSchema[2] | Should -Match "$tableName"
        }
    }
    Context "Should create graph tables with IsNode and IsEdge switches" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
            $skipGraphTests = $server.VersionMajor -lt 14
            if (-not $skipGraphTests) {
                $graphDbName = "dbatoolsscidb_graph_$(Get-Random)"
                $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $graphDbName
            }
        }
        AfterAll {
            if (-not $skipGraphTests) {
                $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $graphDbName -Confirm:$false
            }
        }
        It "Creates a node table when -IsNode is specified" -Skip:$skipGraphTests {
            $map = @{
                Name     = "NodeId"
                Type     = "int"
                Nullable = $false
            }
            $result = New-DbaDbTable -SqlInstance $TestConfig.InstanceMulti2 -Database $graphDbName -Name $tablenameNode -ColumnMap $map -IsNode
            $result.Name | Should -Be $tablenameNode
            $result.IsNode | Should -BeTrue
        }
        It "Creates an edge table when -IsEdge is specified" -Skip:$skipGraphTests {
            $map = @{
                Name      = "EdgeProperty"
                Type      = "varchar"
                MaxLength = 50
                Nullable  = $true
            }
            $result = New-DbaDbTable -SqlInstance $TestConfig.InstanceMulti2 -Database $graphDbName -Name $tablenameEdge -ColumnMap $map -IsEdge
            $result.Name | Should -Be $tablenameEdge
            $result.IsEdge | Should -BeTrue
        }
    }
}