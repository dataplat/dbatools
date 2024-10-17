param($ModuleName = 'dbatools')

Describe "Remove-DbaCredential" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaCredential
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type String[]
        }
        It "Should have ExcludeCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeCredential -Type String[]
        }
        It "Should have Identity as a parameter" {
            $CommandUnderTest | Should -HaveParameter Identity -Type String[]
        }
        It "Should have ExcludeIdentity as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeIdentity -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Credential[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $env:instance2
            $credentialName = "dbatoolsci_test_$(Get-Random)"
            $credentialName2 = "dbatoolsci_test_$(Get-Random)"

            Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL $credentialName WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL $credentialName2 WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"
        }

        AfterAll {
            # Cleanup any remaining test credentials
            $remainingCredentials = Get-DbaCredential -SqlInstance $server | Where-Object { $_.Name -like 'dbatoolsci_test_*' }
            foreach ($cred in $remainingCredentials) {
                Remove-DbaCredential -SqlInstance $server -Credential $cred.Name -Confirm:$false
            }
        }

        It "removes a SQL credential" {
            Get-DbaCredential -SqlInstance $server -Credential $credentialName | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $server -Credential $credentialName -Confirm:$false
            Get-DbaCredential -SqlInstance $server -Credential $credentialName | Should -BeNullOrEmpty
        }

        It "supports piping SQL credential" {
            Get-DbaCredential -SqlInstance $server -Credential $credentialName2 | Should -Not -BeNullOrEmpty
            Get-DbaCredential -SqlInstance $server -Credential $credentialName2 | Remove-DbaCredential -Confirm:$false
            Get-DbaCredential -SqlInstance $server -Credential $credentialName2 | Should -BeNullOrEmpty
        }

        It "removes all SQL credentials but excluded" {
            $excludedCredential = "dbatoolsci_test_$(Get-Random)"
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL $excludedCredential WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"

            Get-DbaCredential -SqlInstance $server -Credential $excludedCredential | Should -Not -BeNullOrEmpty
            Get-DbaCredential -SqlInstance $server -ExcludeCredential $excludedCredential | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $server -ExcludeCredential $excludedCredential -Confirm:$false
            Get-DbaCredential -SqlInstance $server -ExcludeCredential $excludedCredential | Should -BeNullOrEmpty
            Get-DbaCredential -SqlInstance $server -Credential $excludedCredential | Should -Not -BeNullOrEmpty

            # Cleanup
            Remove-DbaCredential -SqlInstance $server -Credential $excludedCredential -Confirm:$false
        }

        It "removes all SQL credentials" {
            # Create some test credentials
            $testCredential1 = "dbatoolsci_test_$(Get-Random)"
            $testCredential2 = "dbatoolsci_test_$(Get-Random)"
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL $testCredential1 WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL $testCredential2 WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"

            Get-DbaCredential -SqlInstance $server | Where-Object { $_.Name -like 'dbatoolsci_test_*' } | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $server -Confirm:$false
            Get-DbaCredential -SqlInstance $server | Where-Object { $_.Name -like 'dbatoolsci_test_*' } | Should -BeNullOrEmpty
        }
    }
}
