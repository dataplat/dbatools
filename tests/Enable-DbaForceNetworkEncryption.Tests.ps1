param($ModuleName = 'dbatools')

Describe "Enable-DbaForceNetworkEncryption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaForceNetworkEncryption
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Microsoft.SqlServer.Management.Smo.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $results = Enable-DbaForceNetworkEncryption -SqlInstance $global:instance1 -EnableException
        }

        It "returns true" {
            $results.ForceEncryption | Should -Be $true
        }
    }
}
