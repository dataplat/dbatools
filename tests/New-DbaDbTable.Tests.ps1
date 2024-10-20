param($ModuleName = 'dbatools')

Describe "New-DbaDbTable" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $dbname = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname
        $tablename = "dbatoolssci_$(Get-Random)"
        $tablename2 = "dbatoolssci2_$(Get-Random)"
        $tablename3 = "dbatoolssci3_$(Get-Random)"
        $tablename4 = "dbatoolssci4_$(Get-Random)"
        $tablename5 = "dbatoolssci5_$(Get-Random)"
    }

    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $global:instance1 -Database $dbname -Query "drop table if exists $tablename, $tablename2, $tablename3, $tablename4, $tablename5"
        $null = Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbTable
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Name",
            "Schema",
            "ColumnMap",
            "ColumnObject"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Should create the table" {
        BeforeAll {
            $map = @{
                Name      = 'test'
                Type      = 'varchar'
                MaxLength = 20
                Nullable  = $true
            }
        }
        It "Creates the table" {
            $result = New-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Name $tablename -ColumnMap $map
            $result.Name | Should -Contain $tablename
        }
        It "Really created it" {
            $tables = Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname
            $tables.Name | Should -Contain $tablename
        }
    }

    Context "Should create the table with constraint on column" {
        BeforeAll {
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
            $result = New-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Name $tablename2 -ColumnMap $map
            $result.Name | Should -Contain $tablename2
        }
        It "Has a default constraint" {
            $table = Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table $tablename2
            $table.Name | Should -Be $tablename2
            $table.Columns.DefaultConstraint.Name | Should -Contain "DF_MyTest"
        }
    }

    Context "Should create the table with an identity column" {
        BeforeAll {
            $map = @{
                Name              = 'testId'
                Type              = 'int'
                Identity          = $true
                IdentitySeed      = 10
                IdentityIncrement = 2
            }
        }
        It "Creates the table" {
            $result = New-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Name $tablename3 -ColumnMap $map
            $result.Name | Should -Contain $tablename3
        }
        It "Has an identity column" {
            $table = Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table $tablename3
            $table.Name | Should -Be $tablename3
            $table.Columns.Identity | Should -BeTrue
            $table.Columns.IdentitySeed | Should -Be $map.IdentitySeed
            $table.Columns.IdentityIncrement | Should -Be $map.IdentityIncrement
        }
    }

    Context "Should create the table with using DefaultExpression and DefaultString" {
        BeforeAll {
            $map = @(
                @{
                    Name              = 'Id'
                    Type              = 'varchar'
                    MaxLength         = 36
                    DefaultExpression = 'NEWID()'
                },
                @{
                    Name          = 'Since'
                    Type          = 'datetime2'
                    DefaultString = '2021-12-31'
                }
            )
        }
        It "Creates the table" {
            { New-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Name $tablename4 -ColumnMap $map -EnableException } | Should -Not -Throw
        }
    }

    Context "Should create the table with a nvarcharmax column" {
        BeforeAll {
            $map = @{
                Name     = 'test'
                Type     = 'nvarchar'
                Nullable = $true
            }
        }
        It "Creates the table" {
            $result = New-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Name $tablename5 -ColumnMap $map
            $result.Name | Should -Contain $tablename5
        }
        It "Has the correct column datatype" {
            $table = Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table $tablename5
            $table.Columns['test'].DataType.SqlDataType | Should -Be "NVarCharMax"
        }
    }

    Context "Should create the schema if it doesn't exist" {
        It "schema created" {
            $random = Get-Random
            $tableName = "table_$random"
            $schemaName = "schema_$random"
            $map = @{
                Name = 'testId'
                Type = 'int'
            }

            $tableWithSchema = New-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Name $tableName -ColumnMap $map -Schema $schemaName
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
                Name = 'testId'
                Type = 'int'
            }

            $tableWithSchema = New-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Name $tableName -ColumnMap $map -Schema $schemaName -Passthru
            $tableWithSchema[0] | Should -Be "CREATE SCHEMA [$schemaName]"
            $tableWithSchema[2] | Should -Match "$schemaName"
            $tableWithSchema[2] | Should -Match "$tableName"
        }
    }
}
