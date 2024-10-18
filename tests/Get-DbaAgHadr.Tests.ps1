param($ModuleName = 'dbatools')

Describe "Get-DbaAgHadr" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgHadr
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" -Skip:(-not $env:APPVEYOR) {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance3
        }

        It "returns the correct properties" {
            $results = Get-DbaAgHadr -SqlInstance $global:instance3
            $results.IsHadrEnabled | Should -Be $true
        }
    }
}
