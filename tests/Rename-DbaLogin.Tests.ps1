param($ModuleName = 'dbatools')

Describe "Rename-DbaLogin" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Rename-DbaLogin
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type System.String
        }
        It "Should have NewLogin as a parameter" {
            $CommandUnderTest | Should -HaveParameter NewLogin -Type System.String
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $login = "dbatoolsci_renamelogin"
            $renamed = "dbatoolsci_renamelogin2"
            $password = 'MyV3ry$ecur3P@ssw0rd'
            $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
            $newlogin = New-DbaLogin -SqlInstance $global:instance1 -Login $login -Password $securePassword
        }
        AfterAll {
            $null = Stop-DbaProcess -SqlInstance $global:instance1 -Login $renamed
            $null = Remove-DbaLogin -SqlInstance $global:instance1 -Login $renamed -Confirm:$false
        }

        It "renames the login" {
            $results = Rename-DbaLogin -SqlInstance $global:instance1 -Login $login -NewLogin $renamed
            $results.Status | Should -Be "Successful"
            $results.PreviousLogin | Should -Be $login
            $results.NewLogin | Should -Be $renamed
            Get-DbaLogin -SqlInstance $global:instance1 -login $renamed | Should -Not -BeNullOrEmpty
        }
    }
}
