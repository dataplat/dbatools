param($ModuleName = 'dbatools')

Describe "Get-DbaPlanCache" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPlanCache
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

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
        }

        It "returns correct datatypes" {
            $results = Get-DbaPlanCache -SqlInstance $global:instance1 | Clear-DbaPlanCache -Threshold 1024
            $results.Size | Should -BeOfType [dbasize]
        }
    }
}
