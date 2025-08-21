#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaResourceGovernor",
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
                "ResourcePool",
                "ExcludeResourcePool",
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

        # Explain what needs to be set up for the test:
        # To test copying resource governor settings, we need to create resource pools, workload groups, and a classifier function on the source instance.

        $splatQuery = @{
            SqlInstance   = $TestConfig.instance2
            WarningAction = "SilentlyContinue"
        }

        # Create prod pool and workload
        Invoke-DbaQuery @splatQuery -Query "CREATE RESOURCE POOL dbatoolsci_prod WITH (MAX_CPU_PERCENT = 100, MIN_CPU_PERCENT = 50)"
        Invoke-DbaQuery @splatQuery -Query "CREATE WORKLOAD GROUP dbatoolsci_prodprocessing WITH (IMPORTANCE = MEDIUM) USING dbatoolsci_prod"

        # Create offhours pool and workload
        Invoke-DbaQuery @splatQuery -Query "CREATE RESOURCE POOL dbatoolsci_offhoursprocessing WITH (MAX_CPU_PERCENT = 50, MIN_CPU_PERCENT = 0)"
        Invoke-DbaQuery @splatQuery -Query "CREATE WORKLOAD GROUP dbatoolsci_goffhoursprocessing WITH (IMPORTANCE = LOW) USING dbatoolsci_offhoursprocessing"

        Invoke-DbaQuery @splatQuery -Query "ALTER RESOURCE GOVERNOR RECONFIGURE"

        # Create and set classifier function
        Invoke-DbaQuery @splatQuery -Query "CREATE FUNCTION dbatoolsci_fnRG() RETURNS sysname WITH SCHEMABINDING AS BEGIN RETURN N'dbatoolsci_goffhoursprocessing' END"
        Invoke-DbaQuery @splatQuery -Query "ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG); ALTER RESOURCE GOVERNOR RECONFIGURE;"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatCleanup = @{
            SqlInstance   = $TestConfig.instance2, $TestConfig.instance3
            WarningAction = "SilentlyContinue"
        }

        Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue

        # Cleanup all created objects.
        Invoke-DbaQuery @splatCleanup -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaQuery @splatCleanup -Query "DROP FUNCTION [dbo].[dbatoolsci_fnRG];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP WORKLOAD GROUP [dbatoolsci_prodprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP WORKLOAD GROUP [dbatoolsci_goffhoursprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP RESOURCE POOL [dbatoolsci_offhoursprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP RESOURCE POOL [dbatoolsci_prod];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying resource governor settings" {
        It "Copies the resource governor successfully" {
            $splatCopyRG = @{
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                Force         = $true
                WarningAction = "SilentlyContinue"
            }

            $results = Copy-DbaResourceGovernor @splatCopyRG
            $results.Status | Select-Object -Unique | Should -BeExactly "Successful"
            $results.Status.Count | Should -BeGreaterThan 3
            $results.Name | Should -Contain "dbatoolsci_prod"
        }

        It "Returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $TestConfig.instance3
            $results.Name | Should -BeExactly "dbatoolsci_fnRG"
        }
    }
}