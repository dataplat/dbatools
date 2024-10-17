param($ModuleName = 'dbatools')

Describe "Rename-DbaLogin" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Rename-DbaLogin
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String
        }
        It "Should have NewLogin as a parameter" {
            $CommandUnderTest | Should -HaveParameter NewLogin -Type String
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $login = "dbatoolsci_renamelogin"
            $renamed = "dbatoolsci_renamelogin2"
            $password = 'MyV3ry$ecur3P@ssw0rd'
            $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
            $newlogin = New-DbaLogin -SqlInstance $script:instance1 -Login $login -Password $securePassword
        }
        AfterAll {
            $null = Stop-DbaProcess -SqlInstance $script:instance1 -Login $renamed
            $null = Remove-DbaLogin -SqlInstance $script:instance1 -Login $renamed -Confirm:$false
        }

        It "renames the login" {
            $results = Rename-DbaLogin -SqlInstance $script:instance1 -Login $login -NewLogin $renamed
            $results.Status | Should -Be "Successful"
            $results.PreviousLogin | Should -Be $login
            $results.NewLogin | Should -Be $renamed
            Get-DbaLogin -SqlInstance $script:instance1 -login $renamed | Should -Not -BeNullOrEmpty
        }
    }
}
