#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbSequence",
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
                "Sequence",
                "Schema",
                "IntegerType",
                "StartWith",
                "IncrementBy",
                "MinValue",
                "MaxValue",
                "Cycle",
                "CacheSize",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $newDbName = "dbatoolsci_newdb_$random"
        $newDb = New-DbaDatabase -SqlInstance $server -Name $newDbName

        $newDb.Query("CREATE SCHEMA TestSchema")
        $newDb.Query("CREATE TYPE TestSchema.NonNullInteger FROM INTEGER NOT NULL")
        $newDb.Query("CREATE TYPE dbo.NonNullInteger FROM INTEGER NOT NULL")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $newDb | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {

        It "validates required Database param" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Name SequenceTest -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "Database is required when SqlInstance is specified"
            $sequence | Should -BeNullOrEmpty
        }

        It "validates IncrementBy param cannot be 0" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name SequenceTest -IncrementBy 0 -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "cannot be zero"
            $sequence | Should -BeNullOrEmpty
        }

        It "creates a new sequence" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random"
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.Parent.Name | Should -Be $newDbName
        }

        It "tries to create a duplicate sequence" {
            $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "Sequence Sequence1_$random already exists in the Schema_$random schema in the database dbatoolsci_newdb_$random"
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