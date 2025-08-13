#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbSequence",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Sequence",
                "Schema",
                "RestartWith",
                "IncrementBy",
                "MinValue",
                "MaxValue",
                "Cycle",
                "CacheSize",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $seqRandom = Get-Random
        $serverInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $testDbName = "dbatoolsci_newdb_$seqRandom"
        $testDatabase = New-DbaDatabase -SqlInstance $serverInstance -Name $testDbName

        $sequenceName = "Sequence1_$seqRandom"
        $schemaName = "Schema_$seqRandom"
        $testSequence = New-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = $testDatabase | Remove-DbaDatabase -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "commands work as expected" {

        It "validates required Database param" {
            $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Sequence $sequenceName -Schema $schemaName -Confirm:$false -WarningVariable WarnVar -WarningAction SilentlyContinue
            $sequence | Should -BeNullOrEmpty
            $WarnVar | Should -Match "Database is required when SqlInstance is specified"
        }

        It "supports piping databases" {
            $sequence = Get-DbaDatabase -SqlInstance $serverInstance -Database $testDbName | Set-DbaDbSequence -Sequence $sequenceName -Schema $schemaName -Cycle -Confirm:$false
            $sequence.Name | Should -Be $sequenceName
            $sequence.Schema | Should -Be $schemaName
            $sequence.Parent.Name | Should -Be $testDbName
            $sequence.IsCycleEnabled | Should -Be $true
        }

        It "updates a sequence with different start values" {
            $startValues = @(-100000, -10, 0, 1, 1000)

            foreach ($startValue in $startValues) {
                $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName -RestartWith $startValue -Confirm:$false
                $sequence.Name | Should -Be $sequenceName
                $sequence.Schema | Should -Be $schemaName
                $sequence.StartValue | Should -Be $startValue
                $sequence.Parent.Name | Should -Be $testDbName
            }
        }

        It "updates a sequence with different increment by values" {
            $incrementByValues = @(-1, 1, 10)

            foreach ($incrementByValue in $incrementByValues) {
                $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName -IncrementBy $incrementByValue -Confirm:$false
                $sequence.Name | Should -Be $sequenceName
                $sequence.Schema | Should -Be $schemaName
                $sequence.IncrementValue | Should -Be $incrementByValue
                $sequence.Parent.Name | Should -Be $testDbName
            }
        }

        It "updates a sequence with min and max values" {
            $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName -MinValue 0 -MaxValue 100000 -Confirm:$false
            $sequence.Name | Should -Be $sequenceName
            $sequence.Schema | Should -Be $schemaName
            $sequence.MinValue | Should -Be 0
            $sequence.MaxValue | Should -Be 100000
            $sequence.Parent.Name | Should -Be $testDbName
        }

        It "updates a sequence with cycle options" {
            $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName -Cycle -Confirm:$false
            $sequence.Name | Should -Be $sequenceName
            $sequence.Schema | Should -Be $schemaName
            $sequence.IsCycleEnabled | Should -Be $true
            $sequence.Parent.Name | Should -Be $testDbName

            $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName -Cycle:$false -Confirm:$false
            $sequence.Name | Should -Be $sequenceName
            $sequence.Schema | Should -Be $schemaName
            $sequence.IsCycleEnabled | Should -Be $false
            $sequence.Parent.Name | Should -Be $testDbName
        }

        It "updates a sequence with cache options" {
            $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName -CacheSize 0 -Confirm:$false
            $sequence.Name | Should -Be $sequenceName
            $sequence.Schema | Should -Be $schemaName
            $sequence.SequenceCacheType | Should -Be NoCache
            $sequence.Parent.Name | Should -Be $testDbName

            $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName -Confirm:$false
            $sequence.Name | Should -Be $sequenceName
            $sequence.Schema | Should -Be $schemaName
            $sequence.SequenceCacheType | Should -Be DefaultCache
            $sequence.Parent.Name | Should -Be $testDbName

            $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName -CacheSize 1000 -Confirm:$false
            $sequence.Name | Should -Be $sequenceName
            $sequence.Schema | Should -Be $schemaName
            $sequence.SequenceCacheType | Should -Be CacheWithSize
            $sequence.CacheSize | Should -Be 1000
            $sequence.Parent.Name | Should -Be $testDbName
        }

        It "validates IncrementBy param cannot be 0" {
            $sequence = Set-DbaDbSequence -SqlInstance $serverInstance -Database $testDbName -Sequence $sequenceName -Schema $schemaName -IncrementBy 0 -Confirm:$false -WarningAction SilentlyContinue -WarningVariable WarnVar
            $sequence | Should -BeNullOrEmpty
            $WarnVar | Should -Match "cannot be zero"
        }
    }
}