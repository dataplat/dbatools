#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $tempguid = [guid]::newguid()
        $DBUserName = "dbatoolssci_$($tempguid.guid)"
        $DBUserName2 = "dbatoolssci2_$($tempguid.guid)"
        $CreateTestUser = @"
CREATE LOGIN [$DBUserName]
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
        Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $CreateTestUser -Database master

        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $DropTestUser = @"
DROP USER [$DBUserName];
DROP USER [$DBUserName2];
DROP LOGIN [$DBUserName];
DROP LOGIN [$DBUserName2];
"@
        Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $DropTestUser -Database master -ErrorAction SilentlyContinue
    }

    Context "Users are correctly located" {
        BeforeAll {
            $results1 = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -eq $DBUserName | Select-Object *
            $results2 = Get-DbaDbUser -SqlInstance $TestConfig.instance2

            $resultsByUser = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database master -User $DBUserName2
            $resultsByMultipleUser = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -User $DBUserName, $DBUserName2

            $resultsByLogin = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Database master -Login $DBUserName2
            $resultsByMultipleLogin = Get-DbaDbUser -SqlInstance $TestConfig.instance2 -Login $DBUserName, $DBUserName2
        }

        It "Should execute and return results" {
            $results2 | Should -Not -Be $null
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -Be $null
        }

        It "Should have matching login and username of $DBUserName" {
            $results1.name | Should -Be $DBUserName
            $results1.login | Should -Be $DBUserName
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