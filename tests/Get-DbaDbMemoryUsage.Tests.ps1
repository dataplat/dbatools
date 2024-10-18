param($ModuleName = 'dbatools')

Describe "Get-DbaDbMemoryUsage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMemoryUsage
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Microsoft.SqlServer.Management.Smo.Database[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[]
        }
        It "Should have IncludeSystemDb as a parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDb -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $instance = Connect-DbaInstance -SqlInstance $global:instance2
        }

        It 'Returns data' {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb
            $result.Count | Should -BeGreaterOrEqual 1
        }

        It 'Accepts a list of databases' {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -Database 'ResourceDb' -IncludeSystemDb

            $uniqueDbs = $result.Database | Select-Object -Unique
            $uniqueDbs | Should -Be 'ResourceDb'
        }

        It 'Excludes databases' {
            $result = Get-DbaDbMemoryUsage -SqlInstance $instance -IncludeSystemDb -ExcludeDatabase 'ResourceDb'

            $uniqueDbs = $result.Database | Select-Object -Unique
            $uniqueDbs | Should -Not -Contain 'ResourceDb'
            $uniqueDbs | Should -Contain 'master'
        }
    }
}
