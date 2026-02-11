#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaMigrationConstraint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
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

        Get-DbaProcess -SqlInstance $TestConfig.InstanceCopy1 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $db1 = "dbatoolsci_testMigrationConstraint"
        $db2 = "dbatoolsci_testMigrationConstraint_2"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "CREATE DATABASE $db1"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "CREATE DATABASE $db2"
        $needed = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $db1, $db2
        $setupright = $true
        if ($needed.Count -ne 2) {
            $setupright = $false
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $db1, $db2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When setup is successful" {
        It "Should have setup correctly" {
            $setupright | Should -Be $true
        }
    }

    Context "Validate multiple databases" {
        It "Both databases are migratable" {
            $results = Test-DbaMigrationConstraint -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2
            foreach ($result in $results) {
                $result.IsMigratable | Should -Be $true
            }
        }
    }

    Context "Validate single database" {
        It "Databases are migratable" {
            (Test-DbaMigrationConstraint -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Database $db1).IsMigratable | Should -Be $true
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Use same instance as source and destination to avoid version mismatch issues
            $outputResult = Test-DbaMigrationConstraint -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy1 -Database $db1
        }

        It "Returns output of the expected type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProperties = @(
                "SourceInstance",
                "DestinationInstance",
                "SourceVersion",
                "DestinationVersion",
                "Database",
                "FeaturesInUse",
                "IsMigratable",
                "Notes"
            )
            foreach ($prop in $expectedProperties) {
                $outputResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}