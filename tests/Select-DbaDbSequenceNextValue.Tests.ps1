$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Sequence', 'Schema', 'InputObject', 'EnableException'
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

        $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random" -StartWith 100
    }

    AfterAll {
        $null = $newDb | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {

        It "validates required Database param" {
            $sequenceValue = Select-DbaDbSequenceNextValue -SqlInstance $server -Sequence SequenceTest -ErrorVariable error
            $sequenceValue | Should -BeNullOrEmpty
            $error | Should -Match "Database is required when SqlInstance is specified"
        }

        It "selects the next value of a sequence" {
            $sequenceValue = Select-DbaDbSequenceNextValue -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $sequenceValue | Should -Be 100

            $sequenceValue = Select-DbaDbSequenceNextValue -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $sequenceValue | Should -Be 101
        }

        It "supports piping databases" {
            $sequenceValue = Get-DbaDatabase -SqlInstance $server -Database $newDbName | Select-DbaDbSequenceNextValue -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $sequenceValue | Should -Be 102
        }
    }
}