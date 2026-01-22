#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Repair-DbaDbOrphanUser",
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
                "Users",
                "RemoveNotExisting",
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

        $loginSql = @"
CREATE LOGIN [dbatoolsci_orphan1] WITH PASSWORD = N'password1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan2] WITH PASSWORD = N'password2', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan3] WITH PASSWORD = N'password3', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE DATABASE dbatoolsci_orphan;
"@
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Invoke-DbaQuery -SqlInstance $server -Query $loginSql
        $userSql = @"
CREATE USER [dbatoolsci_orphan1] FROM LOGIN [dbatoolsci_orphan1];
CREATE USER [dbatoolsci_orphan2] FROM LOGIN [dbatoolsci_orphan2];
CREATE USER [dbatoolsci_orphan3] FROM LOGIN [dbatoolsci_orphan3];
"@
        Invoke-DbaQuery -SqlInstance $server -Query $userSql -Database dbatoolsci_orphan
        $dropOrphan = "DROP LOGIN [dbatoolsci_orphan1];DROP LOGIN [dbatoolsci_orphan2];"
        Invoke-DbaQuery -SqlInstance $server -Query $dropOrphan
        $recreateLoginSql = @"
CREATE LOGIN [dbatoolsci_orphan1] WITH PASSWORD = N'password1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan2] WITH PASSWORD = N'password2', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
"@
        Invoke-DbaQuery -SqlInstance $server -Query $recreateLoginSql

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Get-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 | Remove-DbaLogin -Force
        $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "shows time taken for preparation" {
        1 | Should -Be 1
    }

    Context "When repairing orphaned users" {
        BeforeAll {
            $repairResults = Repair-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database dbatoolsci_orphan
        }

        It "Finds two orphans" {
            $repairResults.Count | Should -Be 2
            foreach ($user in $repairResults) {
                $user.User | Should -BeIn @("dbatoolsci_orphan1", "dbatoolsci_orphan2")
                $user.DatabaseName | Should -Be "dbatoolsci_orphan"
                $user.Status | Should -Be "Success"
            }
        }

        It "has the correct properties" {
            $result = $repairResults[0]
            $expectedProps = "ComputerName,InstanceName,SqlInstance,DatabaseName,User,Status".Split(",")
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }
    }

    Context "When running repair again" {
        It "does not find any other orphan" {
            $secondRepairResults = Repair-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database dbatoolsci_orphan
            $secondRepairResults | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create new orphans for output validation testing
            $createOrphanSql = @"
CREATE USER [dbatoolsci_orphan_output1] WITHOUT LOGIN;
CREATE USER [dbatoolsci_orphan_output2] WITHOUT LOGIN;
"@
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $createOrphanSql -Database dbatoolsci_orphan -EnableException
            $result = Repair-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database dbatoolsci_orphan -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "User",
                "Status"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the correct Status values" {
            $result.Status | Should -BeIn @("Success", "No matching login")
        }
    }
}