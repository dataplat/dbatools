param($ModuleName = 'dbatools')

Describe "Enable-DbaHideInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaHideInstance
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $instance = $global:instance1
        }

        AfterAll {
            $null = Disable-DbaHideInstance -SqlInstance $instance
        }

        It "Enables Hide Instance" {
            $results = Enable-DbaHideInstance -SqlInstance $instance -EnableException
            $results.HideInstance | Should -Be $true
        }
    }
}
