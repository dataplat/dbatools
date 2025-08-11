#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbUser",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "ExcludeSystemUser",
                "User",
                "Login",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $tempguid = [guid]::NewGuid()
        $dbUserName = "dbatoolssci_$($tempguid.guid)"
        $dbUserName2 = "dbatoolssci2_$($tempguid.guid)"
        $createTestUser = @"
CREATE LOGIN [$dbUserName]
    WITH PASSWORD = '$($tempguid.guid)';
USE Master;
CREATE USER [$dbUserName] FOR LOGIN [$dbUserName]
    WITH DEFAULT_SCHEMA = dbo;
CREATE LOGIN [$dbUserName2]
    WITH PASSWORD = '$($tempguid.guid)';
USE Master;
CREATE USER [$dbUserName2] FOR LOGIN [$dbUserName2]
    WITH DEFAULT_SCHEMA = dbo;
"@
        Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $createTestUser -Database master

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $dropTestUser = @"
DROP USER [$dbUserName];
DROP USER [$dbUserName2];
DROP LOGIN [$dbUserName];
DROP LOGIN [$dbUserName2];
"@
        Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $dropTestUser -Database master
    }

    Context "Users are correctly located" {
        BeforeAll {
            $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -eq $dbUserName | Select-Object *
            $results2 = Get-DbaDbUser -SqlInstance $TestConfig.instance2

            $resultsByUser = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database master -User $dbUserName2
            $resultsByMultipleUser = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -User $dbUserName, $dbUserName2

            $resultsByLogin = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database master -Login $dbUserName2
            $resultsByMultipleLogin = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Login $dbUserName, $dbUserName2
        }

        It "Should execute and return results" {
            $results2 | Should -Not -Be $null
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -Be $null
        }

        It "Should have matching login and username of $dbUserName" {
            $results1.Name | Should -Be $dbUserName
            $results1.Login | Should -Be $dbUserName
        }

        It "Should have a login type of SqlLogin" {
            $results1.LoginType | Should -Be "SqlLogin"
        }

        It "Should have DefaultSchema of dbo" {
            $results1.DefaultSchema | Should -Be "dbo"
        }

        It "Should have database access" {
            $results1.HasDBAccess | Should -Be $true
        }

        It "Should not Throw an Error" {
            { Get-DbaDbUser -SqlInstance $TestConfig.instance2 -ExcludeDatabase master -ExcludeSystemUser } | Should -Not -Throw
        }

        It "Should return a specific user" {
            $resultsByUser.Name | Should -Be $dbUserName2
            $resultsByUser.Database | Should -Be "master"
        }

        It "Should return two specific users" {
            $resultsByMultipleUser.Name | Should -Be $dbUserName, $dbUserName2
            $resultsByMultipleUser.Database | Should -Be "master", "master"
        }

        It "Should return a specific user for the given login" {
            $resultsByLogin.Name | Should -Be $dbUserName2
            $resultsByLogin.Database | Should -Be "master"
        }

        It "Should return two specific users for the given logins" {
            $resultsByMultipleLogin.Name | Should -Be $dbUserName, $dbUserName2
            $resultsByMultipleLogin.Database | Should -Be "master", "master"
        }
    }
}