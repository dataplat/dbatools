$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Name', 'Schema', 'RestartWith', 'IncrementBy', 'MinValue', 'MaxValue', 'Cycle', 'CacheSize', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {
        $random = Get-Random
        $instance1 = Connect-DbaInstance -SqlInstance $script:instance1
        $null = Get-DbaProcess -SqlInstance $instance1 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $newDbName = "dbatoolsci_newdb_$random"
        $newDb = New-DbaDatabase -SqlInstance $instance1 -Name $newDbName

        $newSequence = New-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random"
    }

    AfterAll {
        $null = $newDb | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {

        It "validates required Database param" {
            $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Name "Sequence1_$random" -Schema "Schema_$random" -Confirm:$false -ErrorVariable error
            $sequence | Should -BeNullOrEmpty
            $error | Should -Match "Database is required when SqlInstance is specified"
        }

        It "supports piping databases" {
            $sequence = Get-DbaDatabase -SqlInstance $instance1 -Database $newDbName | Set-DbaDbSequence -Name "Sequence1_$random" -Schema "Schema_$random" -Cycle -Confirm:$false
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.Parent.Name | Should -Be $newDbName
            $sequence.IsCycleEnabled | Should -Be $true
        }

        It "updates a sequence with different start values" {
            $startValues = @(-100000, -10, 0, 1, 1000)

            foreach ($startValue in $startValues) {
                $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -RestartWith $startValue -Confirm:$false
                $sequence.Name | Should -Be "Sequence1_$random"
                $sequence.Schema | Should -Be "Schema_$random"
                $sequence.StartValue | Should -Be $startValue
                $sequence.Parent.Name | Should -Be $newDbName
            }
        }

        It "updates a sequence with different increment by values" {
            $incrementByValues = @(-1, 1, 10)

            foreach ($incrementByValue in $incrementByValues) {
                $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -IncrementBy $incrementByValue -Confirm:$false
                $sequence.Name | Should -Be "Sequence1_$random"
                $sequence.Schema | Should -Be "Schema_$random"
                $sequence.IncrementValue | Should -Be $incrementByValue
                $sequence.Parent.Name | Should -Be $newDbName
            }
        }

        It "updates a sequence with min and max values" {
            $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -MinValue 0 -MaxValue 100000 -Confirm:$false
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.MinValue | Should -Be 0
            $sequence.MaxValue | Should -Be 100000
            $sequence.Parent.Name | Should -Be $newDbName
        }

        It "updates a sequence with cycle options" {
            $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -Cycle -Confirm:$false
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.IsCycleEnabled | Should -Be $true
            $sequence.Parent.Name | Should -Be $newDbName

            $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -Cycle:$false -Confirm:$false
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.IsCycleEnabled | Should -Be $false
            $sequence.Parent.Name | Should -Be $newDbName
        }

        It "updates a sequence with cache options" {
            $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -CacheSize 0 -Confirm:$false
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.SequenceCacheType | Should -Be NoCache
            $sequence.Parent.Name | Should -Be $newDbName

            $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -Confirm:$false
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.SequenceCacheType | Should -Be DefaultCache
            $sequence.Parent.Name | Should -Be $newDbName

            $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -CacheSize 1000 -Confirm:$false
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.SequenceCacheType | Should -Be CacheWithSize
            $sequence.CacheSize | Should -Be 1000
            $sequence.Parent.Name | Should -Be $newDbName
        }

        It "validates IncrementBy param cannot be 0" {
            $sequence = Set-DbaDbSequence -SqlInstance $instance1 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -IncrementBy 0 -Confirm:$false -ErrorVariable error
            $sequence | Should -BeNullOrEmpty
            $error.Exception | Should -Match "cannot be zero"
        }
    }
}