#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbRoleMember",
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
                "User",
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

        $serverInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $testUser1 = "dbatoolssci_user1_$(Get-Random)"
        $testUser2 = "dbatoolssci_user2_$(Get-Random)"
        $testRole = "dbatoolssci_role_$(Get-Random)"
        $testDatabase = "dbatoolsci_$(Get-Random)"

        $splatLogin1 = @{
            SqlInstance = $TestConfig.instance2
            Login       = $testUser1
            Password    = ("Password1234!" | ConvertTo-SecureString -AsPlainText -Force)
        }
        $null = New-DbaLogin @splatLogin1

        $splatLogin2 = @{
            SqlInstance = $TestConfig.instance2
            Login       = $testUser2
            Password    = ("Password1234!" | ConvertTo-SecureString -AsPlainText -Force)
        }
        $null = New-DbaLogin @splatLogin2

        $splatDatabase = @{
            SqlInstance = $TestConfig.instance2
            Name        = $testDatabase
            Owner       = "sa"
        }
        $null = New-DbaDatabase @splatDatabase

        $splatDbUser1 = @{
            SqlInstance = $TestConfig.instance2
            Database    = $testDatabase
            Login       = $testUser1
            Username    = "User1"
        }
        $null = New-DbaDbUser @splatDbUser1

        $splatDbUser2 = @{
            SqlInstance = $TestConfig.instance2
            Database    = $testDatabase
            Login       = $testUser2
            Username    = "User2"
        }
        $null = New-DbaDbUser @splatDbUser2

        $splatDbUser1Msdb = @{
            SqlInstance   = $TestConfig.instance2
            Database      = "msdb"
            Login         = $testUser1
            Username      = "User1"
            IncludeSystem = $true
        }
        $null = New-DbaDbUser @splatDbUser1Msdb

        $splatDbUser2Msdb = @{
            SqlInstance   = $TestConfig.instance2
            Database      = "msdb"
            Login         = $testUser2
            Username      = "User2"
            IncludeSystem = $true
        }
        $null = New-DbaDbUser @splatDbUser2Msdb

        $null = $serverInstance.Query("CREATE ROLE $testRole", $testDatabase)
        $null = $serverInstance.Query("ALTER ROLE $testRole ADD MEMBER User1", $testDatabase)
        $null = $serverInstance.Query("ALTER ROLE db_datareader ADD MEMBER User1", "msdb")
        $null = $serverInstance.Query("ALTER ROLE db_datareader ADD MEMBER User2", "msdb")
        $null = $serverInstance.Query("ALTER ROLE SQLAgentReaderRole ADD MEMBER User1", "msdb")
        $null = $serverInstance.Query("ALTER ROLE SQLAgentReaderRole ADD MEMBER User2", "msdb")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $cleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $cleanupServer.Query("DROP USER User1", "msdb")
        $null = $cleanupServer.Query("DROP USER User2", "msdb")

        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDatabase
        Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $testUser1, $testUser2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        BeforeAll {
            $contextServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        }

        It "Removes Role for User" {
            $roleDB = Get-DbaDbRoleMember -SqlInstance $TestConfig.instance2 -Database $testDatabase -Role $testRole
            Remove-DbaDbRoleMember -SqlInstance $TestConfig.instance2 -Role $testRole -User "User1" -Database $testDatabase
            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $contextServer -Database $testDatabase -Role $testRole

            $roleDB.UserName | Should -Be "User1"
            $roleDBAfter | Should -BeNullOrEmpty
        }

        It "Removes Multiple Roles for User" {
            $roleDB = Get-DbaDbRoleMember -SqlInstance $contextServer -Database "msdb" -Role "db_datareader", "SQLAgentReaderRole"
            $contextServer | Remove-DbaDbRoleMember -Role "db_datareader", "SQLAgentReaderRole" -User "User1" -Database "msdb"

            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $contextServer -Database "msdb" -Role "db_datareader", "SQLAgentReaderRole"
            $roleDB.UserName -contains "User1" | Should -Be $true
            $roleDB.UserName -contains "User2" | Should -Be $true
            $roleDB.Count | Should -BeGreaterThan $roleDBAfter.Count
            $roleDBAfter.UserName -contains "User1" | Should -Be $false
            $roleDBAfter.UserName -contains "User2" | Should -Be $true
        }

        It "Removes Roles for User via piped input from Get-DbaDbRole" {
            $roleInput = Get-DbaDbRole -SqlInstance $contextServer -Database "msdb" -Role "db_datareader", "SQLAgentReaderRole"
            $roleDB = Get-DbaDbRoleMember -SqlInstance $contextServer -Database "msdb" -Role "db_datareader", "SQLAgentReaderRole"
            $roleInput | Remove-DbaDbRoleMember -User "User2"

            $roleDBAfter = Get-DbaDbRoleMember -SqlInstance $contextServer -Database "msdb" -Role "db_datareader", "SQLAgentReaderRole"
            $roleDB.UserName -contains "User2" | Should -Be $true
            $roleDBAfter.UserName -contains "User2" | Should -Be $false
        }
    }
}