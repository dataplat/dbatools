param($ModuleName = 'dbatools')

Describe "Add-DbaDbRoleMember" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaDbRoleMember
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have Role as a parameter" {
            $CommandUnderTest | Should -HaveParameter Role -Type String[]
        }
        It "Should have Member as a parameter" {
            $CommandUnderTest | Should -HaveParameter Member -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $user1 = "dbatoolssci_user1_$(Get-Random)"
            $user2 = "dbatoolssci_user2_$(Get-Random)"
            $role = "dbatoolssci_role_$(Get-Random)"
            $null = New-DbaLogin -SqlInstance $global:instance2 -Login $user1 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
            $null = New-DbaLogin -SqlInstance $global:instance2 -Login $user2 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
            $dbname = "dbatoolsci_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbname -Owner sa
            $null = New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Login $user1 -Username $user1
            $null = New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Login $user2 -Username $user2
            $null = New-DbaDbUser -SqlInstance $global:instance2 -Database msdb -Login $user1 -Username $user1 -IncludeSystem
            $null = New-DbaDbUser -SqlInstance $global:instance2 -Database msdb -Login $user2 -Username $user2 -IncludeSystem
            $null = $server.Query("CREATE ROLE $role", $dbname)
        }

        AfterAll {
            $null = $server.Query("DROP USER $user1", 'msdb')
            $null = $server.Query("DROP USER $user2", 'msdb')
            $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
            $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $user1, $user2 -Confirm:$false
        }

        It 'Adds User to Role' {
            Add-DbaDbRoleMember -SqlInstance $global:instance2 -Role $role -Member $user1 -Database $dbname -Confirm:$false
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database $dbname -Role $role

            $roleDBAfter.Role | Should -Be $role
            $roleDBAfter.Login | Should -Be $user1
            $roleDBAfter.UserName | Should -Be $user1
        }

        It 'Adds User to Multiple Roles' {
            $roleDB = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            Add-DbaDbRoleMember -SqlInstance $global:instance2 -Role db_datareader, SQLAgentReaderRole -Member $user1 -Database msdb -Confirm:$false

            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDBAfter.Count | Should -BeGreaterThan $roleDB.Count
            $roleDB.UserName | Should -Not -Contain $user1
            $roleDBAfter.UserName | Should -Contain $user1
        }

        It 'Adds User to Roles via piped input from Get-DbaDbRole' {
            $roleInput = Get-DbaDbRole -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDB = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleInput | Add-DbaDbRoleMember -User $user2 -Confirm:$false

            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDB.UserName | Should -Not -Contain $user2
            $roleDBAfter.UserName | Should -Contain $user2
        }

        It 'Skip adding user to role if already a member' {
            $messages = Add-DbaDbRoleMember -SqlInstance $global:instance2 -Role $role -Member $user1 -Database $dbname -Confirm:$false -Verbose 4>&1
            $messageCount = ($messages -match 'Adding user').Count

            $messageCount | Should -Be 0
        }

        It 'Adds Role to Role' {
            Add-DbaDbRoleMember -SqlInstance $global:instance2 -Role db_datawriter -Member $role -Database $dbname -Confirm:$false
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database $dbname -Role db_datawriter

            $roleDBAfter.MemberRole | Should -Contain $role
        }
    }
}
