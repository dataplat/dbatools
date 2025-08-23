#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaDbRoleMember",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Role",
                "Member",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $user1 = "dbatoolssci_user1_$(Get-Random)"
        $user2 = "dbatoolssci_user2_$(Get-Random)"
        $role = "dbatoolssci_role_$(Get-Random)"
        $splatLoginUser1 = @{
            SqlInstance = $TestConfig.instance2
            Login       = $user1
            Password    = ("Password1234!" | ConvertTo-SecureString -asPlainText -Force)
        }
        $null = New-DbaLogin @splatLoginUser1
        $splatLoginUser2 = @{
            SqlInstance = $TestConfig.instance2
            Login       = $user2
            Password    = ("Password1234!" | ConvertTo-SecureString -asPlainText -Force)
        }
        $null = New-DbaLogin @splatLoginUser2
        $dbname = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $dbname -Owner sa
        $splatDbUser1 = @{
            SqlInstance = $TestConfig.instance2
            Database    = $dbname
            Login       = $user1
            Username    = $user1
        }
        $null = New-DbaDbUser @splatDbUser1
        $splatDbUser2 = @{
            SqlInstance = $TestConfig.instance2
            Database    = $dbname
            Login       = $user2
            Username    = $user2
        }
        $null = New-DbaDbUser @splatDbUser2
        $splatDbUser1Msdb = @{
            SqlInstance   = $TestConfig.instance2
            Database      = "msdb"
            Login         = $user1
            Username      = $user1
            IncludeSystem = $true
        }
        $null = New-DbaDbUser @splatDbUser1Msdb
        $splatDbUser2Msdb = @{
            SqlInstance   = $TestConfig.instance2
            Database      = "msdb"
            Login         = $user2
            Username      = $user2
            IncludeSystem = $true
        }
        $null = New-DbaDbUser @splatDbUser2Msdb
        $null = $server.Query("CREATE ROLE $role", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("DROP USER $user1", "msdb")
        $null = $server.Query("DROP USER $user2", "msdb")
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $user1, $user2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding a user to a role" {
        BeforeAll {
            $splatAddRoleMember = @{
                SqlInstance = $TestConfig.instance2
                Role        = $role
                Member      = $user1
                Database    = $dbname
            }
            $result = Add-DbaDbRoleMember @splatAddRoleMember
            $splatGetRoleMember = @{
                SqlInstance = $server
                Database    = $dbname
                Role        = $role
            }
            $roleDBAfter = Get-DbaDbRoleMember @splatGetRoleMember
        }

        It "Adds the user to the role" {
            $roleDBAfter.Role | Should -Be $role
            $roleDBAfter.Login | Should -Be $user1
            $roleDBAfter.UserName | Should -Be $user1
        }
    }

    Context "When adding a user to multiple roles" {
        BeforeAll {
            $splatGetRoleMemberBefore = @{
                SqlInstance = $server
                Database    = "msdb"
                Role        = @("db_datareader", "SQLAgentReaderRole")
            }
            $roleDB = Get-DbaDbRoleMember @splatGetRoleMemberBefore
            $splatAddMultipleRoles = @{
                SqlInstance = $TestConfig.instance2
                Role        = @("db_datareader", "SQLAgentReaderRole")
                Member      = $user1
                Database    = "msdb"
            }
            $result = Add-DbaDbRoleMember @splatAddMultipleRoles
            $splatGetRoleMemberAfter = @{
                SqlInstance = $server
                Database    = "msdb"
                Role        = @("db_datareader", "SQLAgentReaderRole")
            }
            $roleDBAfter = Get-DbaDbRoleMember @splatGetRoleMemberAfter
        }

        It "Adds the user to multiple roles" {
            $roleDBAfter.Count | Should -BeGreaterThan $roleDB.Count
            $roleDB.UserName | Should -Not -Contain $user1
            $roleDBAfter.UserName | Should -Contain $user1
        }
    }

    Context "When adding a user to roles via piped input from Get-DbaDbRole" {
        BeforeAll {
            $splatGetDbRole = @{
                SqlInstance = $server
                Database    = "msdb"
                Role        = @("db_datareader", "SQLAgentReaderRole")
            }
            $roleInput = Get-DbaDbRole @splatGetDbRole
            $splatGetRoleMemberPipe = @{
                SqlInstance = $server
                Database    = "msdb"
                Role        = @("db_datareader", "SQLAgentReaderRole")
            }
            $roleDB = Get-DbaDbRoleMember @splatGetRoleMemberPipe
            $result = $roleInput | Add-DbaDbRoleMember -User $user2
            $splatGetRoleMemberPipeAfter = @{
                SqlInstance = $server
                Database    = "msdb"
                Role        = @("db_datareader", "SQLAgentReaderRole")
            }
            $roleDBAfter = Get-DbaDbRoleMember @splatGetRoleMemberPipeAfter
        }

        It "Adds the user to roles via piped input" {
            $roleDB.UserName | Should -Not -Contain $user2
            $roleDBAfter.UserName | Should -Contain $user2
        }
    }

    Context "When adding a user to a role they are already a member of" {
        BeforeAll {
            $splatAddExistingMember = @{
                SqlInstance = $TestConfig.instance2
                Role        = $role
                Member      = $user1
                Database    = $dbname
            }
            $messages = Add-DbaDbRoleMember @splatAddExistingMember
        }

        It "Skips adding the user and outputs appropriate message" {
            $messageCount = ($messages -match "Adding user").Count
            $messageCount | Should -Be 0
        }
    }

    Context "When adding a role to another role" {
        BeforeAll {
            $splatAddRoleToRole = @{
                SqlInstance = $TestConfig.instance2
                Role        = "db_datawriter"
                Member      = $role
                Database    = $dbname
            }
            $result = Add-DbaDbRoleMember @splatAddRoleToRole
            $splatGetRoleToRole = @{
                SqlInstance = $server
                Database    = $dbname
                Role        = "db_datawriter"
            }
            $roleDBAfter = Get-DbaDbRoleMember @splatGetRoleToRole
        }

        It "Adds the role to another role" {
            $roleDBAfter.MemberRole | Should -Contain $role
        }
    }
}