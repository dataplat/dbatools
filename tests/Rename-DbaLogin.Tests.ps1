param($ModuleName = 'dbatools')

Describe "Rename-DbaLogin" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Rename-DbaLogin
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Login",
                "NewLogin",
                "Force",
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
