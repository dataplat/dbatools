param($ModuleName = 'dbatools')

Describe "Get-DbaDump" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDump
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" -Skip:($null -ne $env:appveyor) {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $server.Query("DBCC STACKDUMP")
            $server.Query("DBCC STACKDUMP")
        }

        It "finds at least one dump" {
            $results = Get-DbaDump -SqlInstance $global:instance1
            $results.Count | Should -BeGreaterOrEqual 1
        }
    }
}
