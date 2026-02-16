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

        # Clean up any leftover resource governor objects from previous test runs on both instances.
        # Use DISABLE + RECONFIGURE to move all sessions to default group first, which avoids
        # "active sessions in workload groups" errors that prevent normal RECONFIGURE.
        foreach ($cleanupInstance in @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)) {
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL)" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "ALTER RESOURCE GOVERNOR DISABLE" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "ALTER RESOURCE GOVERNOR RECONFIGURE" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "IF OBJECT_ID('dbo.dbatoolsci_fnRG') IS NOT NULL DROP FUNCTION [dbo].[dbatoolsci_fnRG]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "DROP WORKLOAD GROUP [dbatoolsci_prodprocessing]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "DROP WORKLOAD GROUP [dbatoolsci_goffhoursprocessing]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "DROP RESOURCE POOL [dbatoolsci_offhoursprocessing]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "DROP RESOURCE POOL [dbatoolsci_prod]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "ALTER RESOURCE GOVERNOR RECONFIGURE" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        }

        # Re-enable resource governor on both instances after cleanup (DISABLE sets stored config to disabled)
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "ALTER RESOURCE GOVERNOR RECONFIGURE" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "ALTER RESOURCE GOVERNOR RECONFIGURE" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # Explain what needs to be set up for the test:
        # To test copying resource governor settings, we need to create resource pools, workload groups, and a classifier function on the source instance.

        $splatQuery = @{
            SqlInstance   = $TestConfig.InstanceCopy1
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
        # Cleanup resource governor objects on both instances using DISABLE to avoid active session conflicts
        foreach ($cleanupInstance in @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)) {
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL)" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "ALTER RESOURCE GOVERNOR DISABLE" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "ALTER RESOURCE GOVERNOR RECONFIGURE" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "IF OBJECT_ID('dbo.dbatoolsci_fnRG') IS NOT NULL DROP FUNCTION [dbo].[dbatoolsci_fnRG]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "DROP WORKLOAD GROUP [dbatoolsci_prodprocessing]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "DROP WORKLOAD GROUP [dbatoolsci_goffhoursprocessing]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "DROP RESOURCE POOL [dbatoolsci_offhoursprocessing]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "DROP RESOURCE POOL [dbatoolsci_prod]" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Invoke-DbaQuery -SqlInstance $cleanupInstance -Query "ALTER RESOURCE GOVERNOR RECONFIGURE" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        }
    }

    Context "When copying resource governor settings" {
        It "Copies the resource governor successfully" {
            $splatCopyRG = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Force         = $true
                WarningAction = "SilentlyContinue"
            }

            $results = Copy-DbaResourceGovernor @splatCopyRG
            $results.Status | Select-Object -Unique | Should -BeExactly "Successful"
            $results.Status.Count | Should -BeGreaterThan 3
            $results.Name | Should -Contain "dbatoolsci_prod"
        }

        It "Returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $TestConfig.InstanceCopy2
            $results.Name | Should -BeExactly "dbatoolsci_fnRG"
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Re-run the copy without Force - pools already exist so results will have Skipped status
            # but the output object structure is the same regardless of status
            $splatCopyValidation = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                WarningAction = "SilentlyContinue"
            }
            $global:dbatoolsciOutput = Copy-DbaResourceGovernor @splatCopyValidation
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}