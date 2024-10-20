param($ModuleName = 'dbatools')

Describe "Remove-DbaXESession" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaXESession
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Session",
            "AllSessions",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $null = Get-DbaXESession -SqlInstance $global:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
        }
        AfterAll {
            $null = Get-DbaXESession -SqlInstance $global:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
        }

        It "Imports and removes a session template" {
            $results = Import-DbaXESessionTemplate -SqlInstance $global:instance2 -Template 'Profiler TSQL Duration'
            $results.Name | Should -Be 'Profiler TSQL Duration'

            $null = Get-DbaXESession -SqlInstance $global:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
            $results = Get-DbaXESession -SqlInstance $global:instance2 -Session 'Profiler TSQL Duration'

            $results.Name | Should -BeNullOrEmpty
            $results.Status | Should -BeNullOrEmpty
        }
    }
}
