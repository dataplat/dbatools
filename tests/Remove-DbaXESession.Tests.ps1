$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Session', 'AllSessions', 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
    }
    AfterAll {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
    }
    Context "Test Importing Session Template" {
        $results = Import-DbaXESessionTemplate -SqlInstance $script:instance2 -Template 'Profiler TSQL Duration'

        It "session should exist" {
            $results.Name | Should Be 'Profiler TSQL Duration'
        }

        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
        $results = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Profiler TSQL Duration'

        It "session should no longer exist" {
            $results.Name | Should Be $null
            $results.Status | Should Be $null
        }
    }
}