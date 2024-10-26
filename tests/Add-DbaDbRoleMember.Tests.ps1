#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Add-DbaDbRoleMember" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaDbRoleMember
            $script:expected = $TestConfig.CommonParameters
            $script:expected += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Role",
                "Member",
                "InputObject",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Add-DbaDbRoleMember" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $user1 = "dbatoolssci_user1_$(Get-Random)"
        $user2 = "dbatoolssci_user2_$(Get-Random)"
        $role = "dbatoolssci_role_$(Get-Random)"
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $user1 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $user2 -Password ('Password1234!' | ConvertTo-SecureString -asPlainText -Force)
        $dbname = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbname -Owner sa
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login $user1 -Username $user1
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login $user2 -Username $user2
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database msdb -Login $user1 -Username $user1 -IncludeSystem
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database msdb -Login $user2 -Username $user2 -IncludeSystem
        $null = $server.Query("CREATE ROLE $role", $dbname)
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("DROP USER $user1", 'msdb')
        $null = $server.Query("DROP USER $user2", 'msdb')
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $user1, $user2 -Confirm:$false
    }

    Context "When adding a user to a role" {
        BeforeAll {
            $result = Add-DbaDbRoleMember -SqlInstance $TestConfig.instance2 -Role $role -Member $user1 -Database $dbname -Confirm:$false
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database $dbname -Role $role
        }

        It "Adds the user to the role" {
            $roleDBAfter.Role | Should -Be $role
            $roleDBAfter.Login | Should -Be $user1
            $roleDBAfter.UserName | Should -Be $user1
        }
    }

    Context "When adding a user to multiple roles" {
        BeforeAll {
            $roleDB = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $result = Add-DbaDbRoleMember -SqlInstance $TestConfig.instance2 -Role db_datareader, SQLAgentReaderRole -Member $user1 -Database msdb -Confirm:$false
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
        }

        It "Adds the user to multiple roles" {
            $roleDBAfter.Count | Should -BeGreaterThan $roleDB.Count
            $roleDB.UserName | Should -Not -Contain $user1
            $roleDBAfter.UserName | Should -Contain $user1
        }
    }

    Context "When adding a user to roles via piped input from Get-DbaDbRole" {
        BeforeAll {
            $roleInput = Get-DbaDbRole -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $roleDB = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
            $result = $roleInput | Add-DbaDbRoleMember -User $user2 -Confirm:$false
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database msdb -Role db_datareader, SQLAgentReaderRole
        }

        It "Adds the user to roles via piped input" {
            $roleDB.UserName | Should -Not -Contain $user2
            $roleDBAfter.UserName | Should -Contain $user2
        }
    }

    Context "When adding a user to a role they are already a member of" {
        BeforeAll {
            $messages = Add-DbaDbRoleMember -SqlInstance $TestConfig.instance2 -Role $role -Member $user1 -Database $dbname -Confirm:$false -Verbose 4>&1
        }

        It "Skips adding the user and outputs appropriate message" {
            $messageCount = ($messages -match 'Adding user').Count
            $messageCount | Should -Be 0
        }
    }

    Context "When adding a role to another role" {
        BeforeAll {
            $result = Add-DbaDbRoleMember -SqlInstance $TestConfig.instance2 -Role db_datawriter -Member $role -Database $dbname -Confirm:$false
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $server -Database $dbname -Role db_datawriter
        }

        It "Adds the role to another role" {
            $roleDBAfter.MemberRole | Should -Contain $role
        }
    }
}
