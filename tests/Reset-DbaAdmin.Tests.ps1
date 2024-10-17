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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String
        }
        It "Should have SecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword -Type SecureString
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            $password = ConvertTo-SecureString -Force -AsPlainText resetadmin1
            $cred = New-Object System.Management.Automation.PSCredential ("dbatoolsci_resetadmin", $password)
        }

        AfterAll {
            Get-DbaProcess -SqlInstance $script:instance2 -Login dbatoolsci_resetadmin | Stop-DbaProcess -WarningAction SilentlyContinue
            Get-DbaLogin -SqlInstance $script:instance2 -Login dbatoolsci_resetadmin | Remove-DbaLogin -Confirm:$false
        }

        It "adds the login as sysadmin" {
            $results = Reset-DbaAdmin -SqlInstance $script:instance2 -Login dbatoolsci_resetadmin -SecurePassword $password -Confirm:$false
            $results.Name | Should -Be 'dbatoolsci_resetadmin'
            $results.IsMember("sysadmin") | Should -Be $true
        }
    }
}
