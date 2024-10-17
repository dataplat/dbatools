param($ModuleName = 'dbatools')

Describe "Get-DbaDbMemoryUsage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMemoryUsage
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have IncludeSystemDb as a parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDb -Type Switch
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
