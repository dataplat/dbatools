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
        $null = New-DbaDatabase -SqlInstance $instance2 -Name $newDbName

        $null = New-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random"
        $null = New-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence2_$random" -Schema "Schema_$random"
    }

    AfterAll {
        $null = $newDb | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {

        It "removes a sequence" {
            (Get-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random") | Should -Not -BeNullOrEmpty
            Remove-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random" -Confirm:$false
            (Get-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence1_$random" -Schema "Schema_$random") | Should -BeNullOrEmpty
        }

        It "supports piping sequences" {
            (Get-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence2_$random" -Schema "Schema_$random") | Should -Not -BeNullOrEmpty
            Get-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence2_$random" -Schema "Schema_$random" | Remove-DbaDbSequence -Confirm:$false
            (Get-DbaDbSequence -SqlInstance $instance2 -Database $newDbName -Name "Sequence2_$random" -Schema "Schema_$random") | Should -BeNullOrEmpty
        }
    }
}