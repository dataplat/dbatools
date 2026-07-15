#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbOrphanUser",
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

        $containmentEnabled = (Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName ContainmentEnabled).ConfiguredValue
        if ($containmentEnabled -ne 1) {
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName ContainmentEnabled -Value 1
        }

        $loginsq = @"
CREATE LOGIN [dbatoolsci_orphan1] WITH PASSWORD = N'password1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan2] WITH PASSWORD = N'password2', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan3] WITH PASSWORD = N'password3', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE DATABASE dbatoolsci_orphan;
CREATE DATABASE dbatoolsci_orphan_contained CONTAINMENT = PARTIAL;
"@
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Invoke-DbaQuery -SqlInstance $server -Query $loginsq
        $usersq = @"
CREATE USER [dbatoolsci_orphan1] FROM LOGIN [dbatoolsci_orphan1];
CREATE USER [dbatoolsci_orphan2] FROM LOGIN [dbatoolsci_orphan2];
CREATE USER [dbatoolsci_orphan3] FROM LOGIN [dbatoolsci_orphan3];
"@
        Invoke-DbaQuery -SqlInstance $server -Query $usersq -Database dbatoolsci_orphan
        $specialUsersQuery = @"
CREATE CERTIFICATE [dbatoolsci_orphan_certificate]
    ENCRYPTION BY PASSWORD = N'dbatools.IO'
    WITH SUBJECT = N'dbatoolsci orphan certificate';
CREATE USER [dbatoolsci_certificate_user] FOR CERTIFICATE [dbatoolsci_orphan_certificate];
"@
        Invoke-DbaQuery -SqlInstance $server -Query $specialUsersQuery -Database dbatoolsci_orphan
        Invoke-DbaQuery -SqlInstance $server -Query "CREATE USER [dbatoolsci_contained_user] WITHOUT LOGIN;" -Database dbatoolsci_orphan_contained
        $dropOrphan = "DROP LOGIN [dbatoolsci_orphan1];DROP LOGIN [dbatoolsci_orphan2];"
        Invoke-DbaQuery -SqlInstance $server -Query $dropOrphan

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Get-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 | Remove-DbaLogin -Force
        $null = Get-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan, dbatoolsci_orphan_contained | Remove-DbaDatabase
        if ($containmentEnabled -ne 1) {
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName ContainmentEnabled -Value $containmentEnabled
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When checking for orphan users" {
        BeforeAll {
            $results = @(Get-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database dbatoolsci_orphan)
            $containedResults = @(Get-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database dbatoolsci_orphan_contained)
        }

        It "Shows time taken for preparation" {
            1 | Should -BeExactly 1
        }

        It "finds the expected orphans" {
            $results.Count | Should -BeExactly 3
            foreach ($user in $results) {
                $user.User | Should -BeIn @("dbatoolsci_orphan1", "dbatoolsci_orphan2", "dbatoolsci_certificate_user")
                $user.DatabaseName | Should -Be "dbatoolsci_orphan"
            }
        }

        It "reports certificate users in non-contained databases" {
            $results.User | Should -Contain "dbatoolsci_certificate_user"
        }

        It "does not report contained SQL users as orphans" {
            $containedResults.User | Should -Not -Contain "dbatoolsci_contained_user"
        }

        It "Has the correct properties" {
            $result = $results[0]
            $ExpectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "User",
                "SmoUser"
            )
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}
