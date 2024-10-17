param($ModuleName = 'dbatools')

Describe "Get-DbaDump" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDump
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Integration Tests" -Skip:($env:appveyor) {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $server.Query("DBCC STACKDUMP")
            $server.Query("DBCC STACKDUMP")
        }

        It "finds at least one dump" {
            $results = Get-DbaDump -SqlInstance $script:instance1
            $results.Count | Should -BeGreaterOrEqual 1
        }
    }
}
