param($ModuleName = 'dbatools')

Describe "Remove-DbaDbRoleMember" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $user1 = "dbatoolssci_user1_$(Get-Random)"
        $user2 = "dbatoolssci_user2_$(Get-Random)"
        $role = "dbatoolssci_role_$(Get-Random)"
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login $user1 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaLogin -SqlInstance $global:instance2 -Login $user2 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $dbname = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name $dbname -Owner sa
        $null = New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Login $user1 -Username 'User1'
        $null = New-DbaDbUser -SqlInstance $global:instance2 -Database $dbname -Login $user2 -Username 'User2'
        $null = New-DbaDbUser -SqlInstance $global:instance2 -Database msdb -Login $user1 -Username 'User1' -IncludeSystem
        $null = New-DbaDbUser -SqlInstance $global:instance2 -Database msdb -Login $user2 -Username 'User2' -IncludeSystem

        $null = $server.Query("CREATE ROLE $role", $dbname)
        $null = $server.Query("ALTER ROLE $role ADD MEMBER User1", $dbname)
        $null = $server.Query("ALTER ROLE db_datareader ADD MEMBER User1", 'msdb')
        $null = $server.Query("ALTER ROLE db_datareader ADD MEMBER User2", 'msdb')
        $null = $server.Query("ALTER ROLE SQLAgentReaderRole ADD MEMBER User1", 'msdb')
        $null = $server.Query("ALTER ROLE SQLAgentReaderRole ADD MEMBER User2", 'msdb')
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $null = $server.Query("DROP USER User1", 'msdb')
        $null = $server.Query("DROP USER User2", 'msdb')
        $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname
        $null = Remove-DbaLogin -SqlInstance $global:instance2 -Login $user1, $user2
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbRoleMember
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Role",
                "User",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Functionality" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
        }

        It 'Removes Role for User' {
            $roleDB = Get-DbaDbRoleMember -SqlInstance $global:instance2 -Database $dbname -Role $role
            Remove-DbaDbRoleMember -SqlInstance $global:instance2 -Role $role -User 'User1' -Database $dbname
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database $dbname -Role $role

            $roleDB.UserName | Should -Be 'User1'
            $roleDBAfter | Should -BeNullOrEmpty
        }

        It 'Removes Multiple Roles for User' {
            $roleDB = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $server | Remove-DbaDbRoleMember -Role db_datareader, SQLAgentReaderRole -User 'User1' -Database msdb

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
            $roleInput | Remove-DbaDbRoleMember -User 'User2'

            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDB.UserName | Should -Contain 'User2'
            $roleDBAfter.UserName | Should -Not -Contain 'User2'
        }
    }
}
