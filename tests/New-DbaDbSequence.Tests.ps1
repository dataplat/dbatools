$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Sequence', 'Schema', 'IntegerType', 'StartWith', 'IncrementBy', 'MinValue', 'MaxValue', 'Cycle', 'CacheSize', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $newDbName = "dbatoolsci_newdb_$random"
        $newDb = New-DbaDatabase -SqlInstance $server -Name $newDbName

        $newDb.Query("CREATE SCHEMA TestSchema")
        $newDb.Query("CREATE TYPE TestSchema.NonNullInteger FROM INTEGER NOT NULL")
        $newDb.Query("CREATE TYPE dbo.NonNullInteger FROM INTEGER NOT NULL")
    }

    AfterAll {
        $null = $newDb | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {

        It "validates required Database param" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Name SequenceTest -ErrorVariable error
            $sequence | Should -BeNullOrEmpty
            $error | Should -Match "Database is required when SqlInstance is specified"
        }

        It "validates IncrementBy param cannot be 0" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name SequenceTest -IncrementBy 0 -ErrorVariable error
            $sequence | Should -BeNullOrEmpty
            $error.Exception | Should -Match "cannot be zero"
        }

        It "creates a new sequence" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random"
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.Parent.Name | Should -Be $newDbName
        }

        It "tries to create a duplicate sequence" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random"
            $sequence | Should -BeNullOrEmpty
        }

        It "supports piping databases" {
            $sequence = Get-DbaDatabase -SqlInstance $server -Database $newDbName | New-DbaDbSequence -Name "Sequence2_$random" -Schema "Schema_$random"
            $sequence.Name | Should -Be "Sequence2_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.Parent.Name | Should -Be $newDbName
        }

        It "creates a new sequence with different integer types" {
            $types = @('tinyint', 'smallint', 'int', 'bigint', 'decimal', 'numeric')

            foreach ($type in $types) {
                $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_$($type)_$($random)" -Schema "Schema_$random" -IntegerType $type
                $sequence.Name | Should -Be "Sequence_$($type)_$($random)"
                $sequence.Schema | Should -Be "Schema_$random"
                $sequence.DataType.ToString() | Should -Be $type
                $sequence.Parent.Name | Should -Be $newDbName
            }
        }

        It "creates a new sequence with different start values" {
            $startValues = @(-100000, -10, 0, 1, 1000000)

            foreach ($startValue in $startValues) {
                $randomForStartValues = Get-Random
                $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_$($randomForStartValues)" -Schema "Schema_$random" -StartWith $startValue
                $sequence.Name | Should -Be "Sequence_$($randomForStartValues)"
                $sequence.Schema | Should -Be "Schema_$random"
                $sequence.StartValue | Should -Be $startValue
                $sequence.Parent.Name | Should -Be $newDbName
            }
        }

        It "creates a new sequence with different increment by values" {
            $incrementByValues = @(-1, 1, 10)

            foreach ($incrementByValue in $incrementByValues) {
                $randomForIncrementValues = Get-Random
                $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_$($randomForIncrementValues)" -Schema "Schema_$random" -IncrementBy $incrementByValue
                $sequence.Name | Should -Be "Sequence_$($randomForIncrementValues)"
                $sequence.Schema | Should -Be "Schema_$random"
                $sequence.IncrementValue | Should -Be $incrementByValue
                $sequence.Parent.Name | Should -Be $newDbName
            }
        }

        It "creates a new sequence with different min values" {
            $minValues = @(-10000, 1, 10000)

            foreach ($minValue in $minValues) {
                $randomForMinValues = Get-Random
                $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_$($randomForMinValues)" -Schema "Schema_$random" -MinValue $minValue -StartWith $minValue
                $sequence.Name | Should -Be "Sequence_$($randomForMinValues)"
                $sequence.Schema | Should -Be "Schema_$random"
                $sequence.MinValue | Should -Be $minValue
                $sequence.Parent.Name | Should -Be $newDbName
            }
        }

        It "creates a new sequence with different max values" {
            $maxValues = @(10000, 100000)

            foreach ($maxValue in $maxValues) {
                $randomForMaxValues = Get-Random
                $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_$($randomForMaxValues)" -Schema "Schema_$random" -MaxValue $maxValue
                $sequence.Name | Should -Be "Sequence_$($randomForMaxValues)"
                $sequence.Schema | Should -Be "Schema_$random"
                $sequence.MaxValue | Should -Be $maxValue
                $sequence.Parent.Name | Should -Be $newDbName
            }
        }

        It "creates a new sequence with cycle options" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_with_cycle" -Cycle
            $sequence.Name | Should -Be "Sequence_with_cycle"
            $sequence.Schema | Should -Be "dbo"
            $sequence.IsCycleEnabled | Should -Be $true
            $sequence.Parent.Name | Should -Be $newDbName

            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_without_cycle"
            $sequence.Name | Should -Be "Sequence_without_cycle"
            $sequence.Schema | Should -Be "dbo"
            $sequence.IsCycleEnabled | Should -Be $false
            $sequence.Parent.Name | Should -Be $newDbName
        }

        It "creates a new sequence with cache options" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_with_nocache" -CacheSize 0
            $sequence.Name | Should -Be "Sequence_with_nocache"
            $sequence.Schema | Should -Be "dbo"
            $sequence.SequenceCacheType | Should -Be NoCache
            $sequence.Parent.Name | Should -Be $newDbName

            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_with_defaultcache"
            $sequence.Name | Should -Be "Sequence_with_defaultcache"
            $sequence.Schema | Should -Be "dbo"
            $sequence.SequenceCacheType | Should -Be DefaultCache
            $sequence.Parent.Name | Should -Be $newDbName

            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_with_cache" -CacheSize 1000
            $sequence.Name | Should -Be "Sequence_with_cache"
            $sequence.Schema | Should -Be "dbo"
            $sequence.SequenceCacheType | Should -Be CacheWithSize
            $sequence.CacheSize | Should -Be 1000
            $sequence.Parent.Name | Should -Be $newDbName
        }

        It "creates a new sequence with a user defined integer type" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_with_custom_type_without_schema_prefix" -IntegerType NonNullInteger
            $sequence.Name | Should -Be "Sequence_with_custom_type_without_schema_prefix"
            $sequence.DataType.Name | Should -Be NonNullInteger
            $sequence.DataType.Schema | Should -Be dbo
            $sequence.Parent.Name | Should -Be $newDbName

            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence_with_custom_type" -IntegerType TestSchema.NonNullInteger
            $sequence.Name | Should -Be "Sequence_with_custom_type"
            $sequence.DataType.Name | Should -Be NonNullInteger
            $sequence.DataType.Schema | Should -Be TestSchema
            $sequence.Parent.Name | Should -Be $newDbName
        }

        It "Does not return warning for system schema" {
            $sequence2 = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Schema dbo -Name "Sequence_in_dbo_schema" -IntegerType bigint -WarningVariable warn
            $warn.message | Should -Not -BeLike "*Schema dbo already exists in the database*"
        }
    }
}