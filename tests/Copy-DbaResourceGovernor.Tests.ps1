#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaResourceGovernor" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaResourceGovernor
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "ResourcePool",
                "ExcludeResourcePool",
                "WorkloadGroup",
                "ExcludeWorkloadGroup",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaResourceGovernor" -Tag "IntegrationTests" {
    BeforeAll {
        $splatSetup = @{
            WarningAction = 'SilentlyContinue'
            SqlInstance = $TestConfig.instance2
        }

        # Ensure clean state before setup
        $cleanupQueries = @(
            "IF EXISTS (SELECT 1 FROM sys.resource_governor_configuration WHERE classifier_function_id IS NOT NULL) ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL)",
            "ALTER RESOURCE GOVERNOR RECONFIGURE",
            "IF OBJECT_ID('dbo.dbatoolsci_fnRG') IS NOT NULL DROP FUNCTION dbo.dbatoolsci_fnRG",
            "IF EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = 'dbatoolsci_prodprocessing') DROP WORKLOAD GROUP dbatoolsci_prodprocessing",
            "IF EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = 'dbatoolsci_goffhoursprocessing') DROP WORKLOAD GROUP dbatoolsci_goffhoursprocessing",
            "IF EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = 'dbatoolsci_prod') DROP RESOURCE POOL dbatoolsci_prod",
            "IF EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = 'dbatoolsci_offhoursprocessing') DROP RESOURCE POOL dbatoolsci_offhoursprocessing",
            "ALTER RESOURCE GOVERNOR RECONFIGURE"
        )

        foreach ($query in $cleanupQueries) {
            Invoke-DbaQuery @splatSetup -Query $query
        }

        # Setup test environment
        $setupQueries = @(
            "CREATE RESOURCE POOL dbatoolsci_prod WITH (MAX_CPU_PERCENT = 100, MIN_CPU_PERCENT = 50)",
            "CREATE WORKLOAD GROUP dbatoolsci_prodprocessing WITH (IMPORTANCE = MEDIUM) USING dbatoolsci_prod",
            "CREATE RESOURCE POOL dbatoolsci_offhoursprocessing WITH (MAX_CPU_PERCENT = 50, MIN_CPU_PERCENT = 0)",
            "CREATE WORKLOAD GROUP dbatoolsci_goffhoursprocessing WITH (IMPORTANCE = LOW) USING dbatoolsci_offhoursprocessing",
            "ALTER RESOURCE GOVERNOR RECONFIGURE",
            "CREATE FUNCTION dbo.dbatoolsci_fnRG() RETURNS sysname WITH SCHEMABINDING AS BEGIN RETURN N'dbatoolsci_goffhoursprocessing' END",
            "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG)",
            "ALTER RESOURCE GOVERNOR RECONFIGURE"
        )

        foreach ($query in $setupQueries) {
            Invoke-DbaQuery @splatSetup -Query $query
        }

        # Clean destination before tests
        $splatDestination = @{
            WarningAction = 'SilentlyContinue'
            SqlInstance = $TestConfig.instance3
        }
        foreach ($query in $cleanupQueries) {
            Invoke-DbaQuery @splatDestination -Query $query
        }
    }

    AfterAll {
        $splatCleanup = @{
            WarningAction = 'SilentlyContinue'
            SqlInstance = @($TestConfig.instance2, $TestConfig.instance3)
        }

        foreach ($query in $cleanupQueries) {
            Invoke-DbaQuery @splatCleanup -Query $query
        }
    }

    Context "When copying resource governor configuration" {
        BeforeAll {
            $splatCopy = @{
                Source = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Force = $true
                WarningAction = 'SilentlyContinue'
            }
            $results = Copy-DbaResourceGovernor @splatCopy
        }

        It "Copies all components successfully" {
            $results | Should -Not -BeNullOrEmpty
            $results | Where-Object Type -eq 'Resource Pool' | Select-Object -ExpandProperty Status | Should -Be 'Successful'
            $results | Where-Object Type -eq 'Workload Group' | Select-Object -ExpandProperty Status | Should -Be 'Successful'
            $results | Where-Object Type -eq 'Classifier Function' | Select-Object -ExpandProperty Status | Should -Be 'Successful'
        }

        It "Copies resource pools correctly" {
            $pools = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance3 -ResourcePool "dbatoolsci_*"
            $pools.Name | Should -Contain 'dbatoolsci_prod'
            $pools.Name | Should -Contain 'dbatoolsci_offhoursprocessing'
        }

        It "Copies workload groups correctly" {
            $groups = Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.instance3 -WorkloadGroup "dbatoolsci_*"
            $groups.Name | Should -Contain 'dbatoolsci_prodprocessing'
            $groups.Name | Should -Contain 'dbatoolsci_goffhoursprocessing'
        }

        It "Copies the classifier function" {
            $classifier = Get-DbaRgClassifierFunction -SqlInstance $TestConfig.instance3
            $classifier.Name | Should -Be 'dbatoolsci_fnRG'
            $classifier.IsEnabled | Should -Be $true
        }
    }
}
