param($ModuleName = 'dbatools')

Describe "Repair-DbaDbOrphanUser" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Repair-DbaDbOrphanUser
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have Users parameter" {
            $CommandUnderTest | Should -HaveParameter Users -Type Object[]
        }
        It "Should have RemoveNotExisting parameter" {
            $CommandUnderTest | Should -HaveParameter RemoveNotExisting -Type SwitchParameter
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            $loginsq = @'
CREATE LOGIN [dbatoolsci_orphan1] WITH PASSWORD = N'password1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan2] WITH PASSWORD = N'password2', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan3] WITH PASSWORD = N'password3', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE DATABASE dbatoolsci_orphan;
'@
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = Remove-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 -Force -Confirm:$false
            $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan -Confirm:$false
            $null = Invoke-DbaQuery -SqlInstance $server -Query $loginsq
            $usersq = @'
CREATE USER [dbatoolsci_orphan1] FROM LOGIN [dbatoolsci_orphan1];
CREATE USER [dbatoolsci_orphan2] FROM LOGIN [dbatoolsci_orphan2];
CREATE USER [dbatoolsci_orphan3] FROM LOGIN [dbatoolsci_orphan3];
'@
            Invoke-DbaQuery -SqlInstance $server -Query $usersq -Database dbatoolsci_orphan
            $dropOrphan = "DROP LOGIN [dbatoolsci_orphan1];DROP LOGIN [dbatoolsci_orphan2];"
            Invoke-DbaQuery -SqlInstance $server -Query $dropOrphan
            $loginsq = @'
CREATE LOGIN [dbatoolsci_orphan1] WITH PASSWORD = N'password1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan2] WITH PASSWORD = N'password2', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
'@
            Invoke-DbaQuery -SqlInstance $server -Query $loginsq
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = Remove-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 -Force -Confirm:$false
            $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan -Confirm:$false
        }

        It "Finds two orphans" {
            $results = Repair-DbaDbOrphanUser -SqlInstance $script:instance1 -Database dbatoolsci_orphan
            $results.Count | Should -Be 2
            foreach ($user in $results) {
                $user.User | Should -BeIn @('dbatoolsci_orphan1', 'dbatoolsci_orphan2')
                $user.DatabaseName | Should -Be 'dbatoolsci_orphan'
                $user.Status | Should -Be 'Success'
            }
        }

        It "Has the correct properties" {
            $results = Repair-DbaDbOrphanUser -SqlInstance $script:instance1 -Database dbatoolsci_orphan
            $result = $results[0]
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'DatabaseName', 'User', 'Status'
            $result.PSObject.Properties.Name | Should -Be $ExpectedProps
        }

        It "Does not find any other orphan" {
            $results = Repair-DbaDbOrphanUser -SqlInstance $script:instance1 -Database dbatoolsci_orphan
            $results | Should -BeNullOrEmpty
        }
    }
}
