param($ModuleName = 'dbatools')

Describe "Get-DbaDbMemoryUsage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMemoryUsage
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "IncludeSystemDb",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
