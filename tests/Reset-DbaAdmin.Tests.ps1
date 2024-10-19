param($ModuleName = 'dbatools')

Describe "Reset-DbaAdmin" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Reset-DbaAdmin
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Login",
                "SecurePassword",
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
            $password = ConvertTo-SecureString -Force -AsPlainText resetadmin1
            $cred = New-Object System.Management.Automation.PSCredential ("dbatoolsci_resetadmin", $password)
        }

        AfterAll {
            Get-DbaProcess -SqlInstance $global:instance2 -Login dbatoolsci_resetadmin | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaLogin -SqlInstance $global:instance2 -Login dbatoolsci_resetadmin | Remove-DbaLogin -Confirm:$false
        }

        It "adds the login as sysadmin" {
            $results = Reset-DbaAdmin -SqlInstance $global:instance2 -Login dbatoolsci_resetadmin -SecurePassword $password -Confirm:$false
            $results.Name | Should -Be 'dbatoolsci_resetadmin'
            $results.IsMember("sysadmin") | Should -Be $true
        }
    }
}
