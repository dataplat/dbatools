#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbOrphanUser",
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
                "ExcludeDatabase",
                "User",
                "Force",
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
        $random = Get-Random
        $dbname = "dbatoolsci_$random"
        $login1 = "dbatoolssci_user1_$random"
        $login2 = "dbatoolssci_user2_$random"
        $schema = "dbatoolssci_Schema_$random"
        $securePassword = ConvertTo-SecureString "MyV3ry`$ecur3P@ssw0rd" -AsPlainText -Force
        $plaintext = "BigOlPassword!"

        $null = New-DbaDatabase -SqlInstance $server -Name $dbname -Owner sa

        $loginWindows = "db$random"
        $computerName = ([DbaInstanceParameter]$TestConfig.instance2).ComputerName
        $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $loginWindows, $plaintext -ComputerName $TestConfig.instance2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    BeforeEach {
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login "$computerName\$loginWindows" -Force

        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login $login1 -Username $login1
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login $login2 -Username $login2
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname -Login "$computerName\$loginWindows" -Username "$computerName\$loginWindows" -Force
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database msdb -Login $login1 -Username $login1 -IncludeSystem
        $null = New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database msdb -Login $login2 -Username $login2 -IncludeSystem
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login "$computerName\$loginWindows"
    }
    AfterEach {
        $users = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb
        if ($users.Name -contains $login1) {
            $null = Remove-DbaDbUser $TestConfig.instance2 -Database $dbname, msdb -User $login1
        }
        if ($users.Name -contains $login2) {
            $null = Remove-DbaDbUser $TestConfig.instance2 -Database $dbname, msdb -User $login2
        }
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -ErrorAction SilentlyContinue
        $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $loginWindows -ComputerName $TestConfig.instance2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "Removes Orphan Users" {
        $results0 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $results0.Name -contains $login1 | Should -Be $true
        $results0.Name -contains $login2 | Should -Be $true
        $results0.Count | Should -BeGreaterThan $results1.Count
    }

    It "Removes selected Orphan Users" {
        $results0 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -User $login1
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $results0.Count | Should -BeGreaterThan $results1.Count
        $results1.Name -contains $login1 | Should -Be $false
        $results1.Name -contains $login2 | Should -Be $true
    }

    It "Removes Orphan Users for Database" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database msdb -User $login1, $login2
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb
        $results1 = $results1 | Where-Object { $_.Name -eq $login1 -or $_.Name -eq $login2 }

        $results1.Name -contains $login1 | Should -Be $true
        $results1.Name -contains $login2 | Should -Be $true
        $results1.Database -contains "msdb" | Should -Be $false
        $results1.Database -contains $dbname | Should -Be $true

    }

    It "Removes Orphan Users except for excluded databases" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -ExcludeDatabase msdb -User $login1, $login2
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb
        $results1 = $results1 | Where-Object { $_.Name -eq $login1 -or $_.Name -eq $login2 }

        $results1.Name -contains $login1 | Should -Be $true
        $results1.Name -contains $login2 | Should -Be $true
        $results1.Database -contains "msdb" | Should -Be $true
        $results1.Database -contains $dbname | Should -Be $false
    }

    It "Removes Orphan Users with unmapped logins if force specified" {
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Password $securePassword -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -Password $securePassword -Force

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -User $login1 -Force
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -User $login2 -WarningAction SilentlyContinue
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $results1.Name -contains $login1 | Should -Be $false
        $results1.Name -contains $login2 | Should -Be $true

        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2

    }

    It "Removes Orphan Logins that own Schemas without objects " {
        $sql = "CREATE SCHEMA $schema AUTHORIZATION $login2"
        $server.Query($sql, $dbname)

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb -User $login1, $login2 -Force -WarningAction SilentlyContinue
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname, msdb

        $results1.Name -contains $login1 | Should -Be $false
        $results1.Name -contains $login2 | Should -Be $false

        $sql = "DROP SCHEMA $schema"
        $server.Query($sql, $dbname)
    }

    It "Removes Orphan Logins that own Schemas with objects only if force specified" {
        $sql = "CREATE SCHEMA $schema AUTHORIZATION $login1"
        $server.Query($sql, $dbname)
        $sql = "CREATE SCHEMA $login2 AUTHORIZATION $login2"
        $server.Query($sql, $dbname)
        $sql = "CREATE TABLE $schema.test1(Id int NULL)"
        $server.Query($sql, $dbname)
        $sql = "CREATE TABLE [$login2].test2(Id int NULL)"
        $server.Query($sql, $dbname)

        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database $dbname -User $login1 -WarningAction SilentlyContinue
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database $dbname -User $login2 -Force
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname

        $results1.Name -contains $login1 | Should -Be $true
        $results1.Name -contains $login2 | Should -Be $false

        $sql = "DROP TABLE $schema.test1;DROP TABLE [$login2].test2;DROP SCHEMA $schema;DROP SCHEMA [$login2];"
        $server.Query($sql, $dbname)
    }

    It "Removes the orphaned windows login" {
        $null = Remove-DbaDbOrphanUser -SqlInstance $TestConfig.instance2 -Database $dbname -User "$($TestConfig.instance2)\$loginWindows"
        $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $dbname
        $results1.Name -contains $loginWindows | Should -Be $false
    }
}