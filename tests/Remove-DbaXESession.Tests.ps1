param($ModuleName = 'dbatools')

Describe "Remove-DbaXESession" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaXESession
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Session as a parameter" {
            $CommandUnderTest | Should -HaveParameter Session
        }
        It "Should have AllSessions as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllSessions
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
