$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Name', 'Schema', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Get-DbaProcess -SqlInstance $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $newDbName = "dbatoolsci_newdb_$random"
        $newDbName2 = "dbatoolsci_newdb2_$random"
        $newDb, $newDb2 = New-DbaDatabase -SqlInstance $instance2 -Name $newDbName, $newDbName2

        $sequence = New-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random"
        $sequence2 = New-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence2_$random" -Schema "Schema2_$random"
        $sequence3 = New-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema2_$random"
        $sequence4 = New-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence2_$random" -Schema "Schema_$random"
        $sequence5 = New-DbaDbSequence -SqlInstance $instance2 -Database $newDbName2 -Name "Sequence1_$random" -Schema "Schema_$random"
    }

    AfterAll {
        $null = $newDb, $newDb2 | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {

        It "finds a sequence on an instance" {
            $sequence = Get-DbaDbSequence -SqlInstance $instance2
            $sequence.Count | Should -Be 5
        }

        It "finds a sequence in a single database" {
            $sequence = Get-DbaDbSequence -SqlInstance $instance2 -Database $newDbName
            $sequence.Parent.Name | Select-Object -Unique | Should -Be $newDbName
            $sequence.Count | Should -Be 4
        }

        It "finds a sequence in a single database by schema only" {
            $sequence = Get-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Schema "Schema2_$random"
            $sequence.Parent.Name | Select-Object -Unique | Should -Be $newDbName
            $sequence.Schema | Select-Object -Unique | Should -Be "Schema2_$random"
            $sequence.Count | Should -Be 2
        }

        It "finds a sequence in a single database by schema and by name" {
            $sequence = Get-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random"
            $sequence.Parent.Name | Select-Object -Unique | Should -Be $newDbName
            $sequence.Name | Select-Object -Unique | Should -Be "Sequence1_$random"
            $sequence.Schema | Select-Object -Unique | Should -Be "Schema_$random"
            $sequence.Count | Should -Be 1
        }

        It "finds a sequence on an instance by name only" {
            $sequence = Get-DbaDbSequence -SqlInstance $instance2 -Name "Sequence1_$random"
            $sequence.Name | Select-Object -Unique | Should -Be "Sequence1_$random"
            $sequence.Count | Should -Be 3
        }

        It "finds a sequence on an instance by schema only" {
            $sequence = Get-DbaDbSequence -SqlInstance $instance2 -Schema "Schema2_$random"
            $sequence.Schema | Select-Object -Unique | Should -Be "Schema2_$random"
            $sequence.Count | Should -Be 2
        }

        It "finds a sequence on an instance by schema and name" {
            $sequence = Get-DbaDbSequence -SqlInstance $instance2 -Schema "Schema_$random" -Name "Sequence1_$random"
            $sequence.Schema | Select-Object -Unique | Should -Be "Schema_$random"
            $sequence.Name | Select-Object -Unique | Should -Be "Sequence1_$random"
            $sequence.Count | Should -Be 2
        }

        It "supports piping databases" {
            $sequence = Get-DbaDatabase -SqlInstance $instance2 -Database $newDbName | Get-DbaDbSequence -Name "Sequence1_$random" -Schema "Schema_$random"
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.Parent.Name | Should -Be $newDbName
        }
    }
}