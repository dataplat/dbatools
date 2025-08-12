#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Repair-DbaDbOrphanUser",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
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
                "Users",
                "RemoveNotExisting",
                "Force",
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Explain what needs to be set up for the test:
        # To test orphan user repair, we need to create users in a database and then drop their corresponding logins,
        # making them orphaned users. Then recreate some logins to test the repair functionality.

        # Set variables. They are available in all the It blocks.
        $databaseName = "dbatoolsci_orphan"
        $orphanLogin1 = "dbatoolsci_orphan1"
        $orphanLogin2 = "dbatoolsci_orphan2"
        $orphanLogin3 = "dbatoolsci_orphan3"

        $loginsql = @"
CREATE LOGIN [$orphanLogin1] WITH PASSWORD = N"password1", CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [$orphanLogin2] WITH PASSWORD = N"password2", CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [$orphanLogin3] WITH PASSWORD = N"password3", CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE DATABASE $databaseName;
"@
        $splatConnection = @{
            SqlInstance     = $TestConfig.instance1
            EnableException = $true
        }
        $server = Connect-DbaInstance @splatConnection
        $null = Remove-DbaLogin -SqlInstance $server -Login $orphanLogin1, $orphanLogin2, $orphanLogin3 -Force -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database $databaseName -Confirm:$false
        $null = Invoke-DbaQuery -SqlInstance $server -Query $loginsql

        $usersql = @"
CREATE USER [$orphanLogin1] FROM LOGIN [$orphanLogin1];
CREATE USER [$orphanLogin2] FROM LOGIN [$orphanLogin2];
CREATE USER [$orphanLogin3] FROM LOGIN [$orphanLogin3];
"@
        Invoke-DbaQuery -SqlInstance $server -Query $usersql -Database $databaseName

        $dropOrphanLogins = "DROP LOGIN [$orphanLogin1];DROP LOGIN [$orphanLogin2];"
        Invoke-DbaQuery -SqlInstance $server -Query $dropOrphanLogins

        $recreateLoginsql = @"
CREATE LOGIN [$orphanLogin1] WITH PASSWORD = N"password1", CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [$orphanLogin2] WITH PASSWORD = N"password2", CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
"@
        Invoke-DbaQuery -SqlInstance $server -Query $recreateLoginsql

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $splatConnection = @{
            SqlInstance     = $TestConfig.instance1
            EnableException = $true
        }
        $server = Connect-DbaInstance @splatConnection
        $null = Remove-DbaLogin -SqlInstance $server -Login $orphanLogin1, $orphanLogin2, $orphanLogin3 -Force -Confirm:$false -ErrorAction SilentlyContinue
        $null = Remove-DbaDatabase -SqlInstance $server -Database $databaseName -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When repairing orphan users" {
        BeforeAll {
            $splatRepairOrphans = @{
                SqlInstance = $TestConfig.instance1
                Database    = $databaseName
            }
            $results = Repair-DbaDbOrphanUser @splatRepairOrphans
        }

        It "Finds two orphans" {
            $results.Count | Should -Be 2
            foreach ($user in $results) {
                $user.User | Should -BeIn @($orphanLogin1, $orphanLogin2)
                $user.DatabaseName | Should -Be $databaseName
                $user.Status | Should -Be "Success"
            }
        }

        It "has the correct properties" {
            $result = $results[0]
            $expectedProps = "ComputerName","InstanceName","SqlInstance","DatabaseName","User","Status"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }
    }

    Context "When no orphan users exist" {
        It "does not find any other orphan" {
            $splatNoOrphans = @{
                SqlInstance = $TestConfig.instance1
                Database    = $databaseName
            }
            $results = Repair-DbaDbOrphanUser @splatNoOrphans
            $results | Should -BeNullOrEmpty
        }
    }
}