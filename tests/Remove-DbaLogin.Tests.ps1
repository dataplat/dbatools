param($ModuleName = 'dbatools')

Describe "Remove-DbaLogin" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaLogin
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Login",
                "InputObject",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $login = "dbatoolsci_removelogin"
            $password = 'MyV3ry$ecur3P@ssw0rd'
            $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
            $newlogin = New-DbaLogin -SqlInstance $global:instance1 -Login $login -Password $securePassword
        }

        It "removes the login" {
            $results = Remove-DbaLogin -SqlInstance $global:instance1 -Login $login -Confirm:$false
            $results.Status | Should -Be "Dropped"
            $login1 = Get-DbaLogin -SqlInstance $global:instance1 -login $login
            $login1 | Should -BeNullOrEmpty
        }
    }
}
