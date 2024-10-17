param($ModuleName = 'dbatools')

Describe "Remove-DbaDbMailAccount" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbMailAccount
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Account as a parameter" {
            $CommandUnderTest | Should -HaveParameter Account -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeAccount as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeAccount -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type MailAccount[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $env:instance2
            $accountname = "dbatoolsci_test_$(Get-Random)"
            $accountname2 = "dbatoolsci_test_$(Get-Random)"

            $null = New-DbaDbMailAccount -SqlInstance $server -Name $accountname -EmailAddress admin@ad.local
            $null = New-DbaDbMailAccount -SqlInstance $server -Name $accountname2 -EmailAddress admin@ad.local
        }

        It "removes a database mail account" {
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -Account $accountname -Confirm:$false
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname | Should -BeNullOrEmpty
        }

        It "supports piping database mail account" {
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname | Should -Not -BeNullOrEmpty
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname | Remove-DbaDbMailAccount -Confirm:$false
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname | Should -BeNullOrEmpty
        }

        It "removes all database mail accounts but excluded" {
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname2 | Should -Not -BeNullOrEmpty
            Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2 | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2 -Confirm:$false
            Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2 | Should -BeNullOrEmpty
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname2 | Should -Not -BeNullOrEmpty
        }

        It "removes all database mail accounts" {
            Get-DbaDbMailAccount -SqlInstance $server | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -Confirm:$false
            Get-DbaDbMailAccount -SqlInstance $server | Should -BeNullOrEmpty
        }

        AfterAll {
            # Clean up any remaining test accounts
            Get-DbaDbMailAccount -SqlInstance $server | Where-Object { $_.Name -like "dbatoolsci_test_*" } | Remove-DbaDbMailAccount -Confirm:$false
        }
    }
}
