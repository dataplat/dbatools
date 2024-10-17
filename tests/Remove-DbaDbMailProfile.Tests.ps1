param($ModuleName = 'dbatools')

Describe "Remove-DbaDbMailProfile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbMailProfile
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Profile as a parameter" {
            $CommandUnderTest | Should -HaveParameter Profile -Type String[]
        }
        It "Should have ExcludeProfile as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeProfile -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type MailProfile[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $env:instance2
            $profilename = "dbatoolsci_test_$(Get-Random)"
            $profilename2 = "dbatoolsci_test_$(Get-Random)"

            $null = New-DbaDbMailProfile -SqlInstance $server -Name $profilename
            $null = New-DbaDbMailProfile -SqlInstance $server -Name $profilename2
        }

        It "removes a database mail profile" {
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profilename | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server -Profile $profilename -Confirm:$false
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profilename | Should -BeNullOrEmpty
        }

        It "supports piping database mail profile" {
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profilename | Should -Not -BeNullOrEmpty
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profilename | Remove-DbaDbMailProfile -Confirm:$false
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profilename | Should -BeNullOrEmpty
        }

        It "removes all database mail profiles but excluded" {
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profilename2 | Should -Not -BeNullOrEmpty
            Get-DbaDbMailProfile -SqlInstance $server -ExcludeProfile $profilename2 | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server -ExcludeProfile $profilename2 -Confirm:$false
            Get-DbaDbMailProfile -SqlInstance $server -ExcludeProfile $profilename2 | Should -BeNullOrEmpty
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profilename2 | Should -Not -BeNullOrEmpty
        }

        It "removes all database mail profiles" {
            Get-DbaDbMailProfile -SqlInstance $server | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server -Confirm:$false
            Get-DbaDbMailProfile -SqlInstance $server | Should -BeNullOrEmpty
        }

        AfterAll {
            # Clean up any remaining profiles
            Remove-DbaDbMailProfile -SqlInstance $server -Confirm:$false
        }
    }
}
