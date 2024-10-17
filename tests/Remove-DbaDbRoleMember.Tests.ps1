param($ModuleName = 'dbatools')

Describe "Remove-DbaDbRoleMember" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $user1 = "dbatoolssci_user1_$(Get-Random)"
        $user2 = "dbatoolssci_user2_$(Get-Random)"
        $role = "dbatoolssci_role_$(Get-Random)"
        $null = New-DbaLogin -SqlInstance $script:instance2 -Login $user1 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaLogin -SqlInstance $script:instance2 -Login $user2 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $dbname = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbname -Owner sa
        $null = New-DbaDbUser -SqlInstance $script:instance2 -Database $dbname -Login $user1 -Username 'User1'
        $null = New-DbaDbUser -SqlInstance $script:instance2 -Database $dbname -Login $user2 -Username 'User2'
        $null = New-DbaDbUser -SqlInstance $script:instance2 -Database msdb -Login $user1 -Username 'User1' -IncludeSystem
        $null = New-DbaDbUser -SqlInstance $script:instance2 -Database msdb -Login $user2 -Username 'User2' -IncludeSystem

        $null = $server.Query("CREATE ROLE $role", $dbname)
        $null = $server.Query("ALTER ROLE $role ADD MEMBER User1", $dbname)
        $null = $server.Query("ALTER ROLE db_datareader ADD MEMBER User1", 'msdb')
        $null = $server.Query("ALTER ROLE db_datareader ADD MEMBER User2", 'msdb')
        $null = $server.Query("ALTER ROLE SQLAgentReaderRole ADD MEMBER User1", 'msdb')
        $null = $server.Query("ALTER ROLE SQLAgentReaderRole ADD MEMBER User2", 'msdb')
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = $server.Query("DROP USER User1", 'msdb')
        $null = $server.Query("DROP USER User2", 'msdb')
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $script:instance2 -Login $user1, $user2 -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbRoleMember
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
        It "Should have User as a parameter" {
            $CommandUnderTest | Should -HaveParameter User -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Functionality" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
        }

        It 'Removes Role for User' {
            $roleDB = Get-DbaDbRoleMember -SqlInstance $script:instance2 -Database $dbname -Role $role
            Remove-DbaDbRoleMember -SqlInstance $script:instance2 -Role $role -User 'User1' -Database $dbname -Confirm:$false
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database $dbname -Role $role

            $roleDB.UserName | Should -Be 'User1'
            $roleDBAfter | Should -BeNullOrEmpty
        }

        It 'Removes Multiple Roles for User' {
            $roleDB = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $server | Remove-DbaDbRoleMember -Role db_datareader, SQLAgentReaderRole -User 'User1' -Database msdb -Confirm:$false

            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDB.UserName | Should -Contain 'User1'
            $roleDB.UserName | Should -Contain 'User2'
            $roleDB.Count | Should -BeGreaterThan $roleDBAfter.Count
            $roleDBAfter.UserName | Should -Not -Contain 'User1'
            $roleDBAfter.UserName | Should -Contain 'User2'
        }

        It 'Removes Roles for User via piped input from Get-DbaDbRole' {
            $roleInput = Get-DbaDbRole -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDB = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleInput | Remove-DbaDbRoleMember -User 'User2' -Confirm:$false

            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDB.UserName | Should -Contain 'User2'
            $roleDBAfter.UserName | Should -Not -Contain 'User2'
        }
    }
}
