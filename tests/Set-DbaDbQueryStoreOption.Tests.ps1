#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbQueryStoreOption",
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
                "AllDatabases",
                "State",
                "FlushInterval",
                "CollectionInterval",
                "MaxSize",
                "CaptureMode",
                "CleanupMode",
                "StaleQueryThreshold",
                "MaxPlansPerQuery",
                "WaitStatsCaptureMode",
                "CustomCapturePolicyExecutionCount",
                "CustomCapturePolicyTotalCompileCPUTimeMS",
                "CustomCapturePolicyTotalExecutionCPUTimeMS",
                "CustomCapturePolicyStaleThresholdHours",
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

        # Clean up any existing test databases
        Get-DbaDatabase -SqlInstance $TestConfig.instance1, $TestConfig.instance2 | Where-Object Name -Match "dbatoolsci" | Remove-DbaDatabase -Confirm:$false
        
        # Create test database for Query Store testing
        New-DbaDatabase -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Name dbatoolsciqs

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Clean up test databases
        Get-DbaDatabase -SqlInstance $TestConfig.instance1, $TestConfig.instance2 | Where-Object Name -Match "dbatoolsci" | Remove-DbaDatabase -Confirm:$false
    }

    Context "Query Store option configuration" {
        BeforeAll {
            $allResults = @()
            $allServers = @()
            foreach ($instance in ($TestConfig.instance1, $TestConfig.instance2)) {
                $server = Connect-DbaInstance -SqlInstance $instance
                $allServers += $server
                $results = Get-DbaDbQueryStoreOption -SqlInstance $server -WarningVariable warning 3>&1
                $allResults += [PSCustomObject]@{
                    Instance = $instance
                    Server   = $server
                    Results  = $results
                    Warning  = $warning
                }
            }
        }

        It "Should warn on SQL Server versions below 2016" {
            foreach ($testResult in $allResults) {
                if ($testResult.Server.VersionMajor -lt 13) {
                    $testResult.Warning | Should -Not -BeNullOrEmpty
                }
            }
        }

        It "Should return valid results on supported SQL Server versions" {
            foreach ($testResult in $allResults) {
                if ($testResult.Server.VersionMajor -ge 13) {
                    $result = $testResult.Results | Where-Object Database -eq "dbatoolsciqs"
                    if ($testResult.Server.VersionMajor -lt 16) {
                        $result.ActualState | Should -Be "Off"
                    } else {
                        $result.ActualState | Should -Be "ReadWrite"
                    }
                    $result.MaxStorageSizeInMB | Should -BeGreaterThan 1
                }
            }
        }

        It "Should change the specified parameter to the new value" {
            foreach ($testResult in $allResults) {
                if ($testResult.Server.VersionMajor -ge 13) {
                    $splatSetOptions = @{
                        SqlInstance   = $testResult.Instance
                        Database      = "dbatoolsciqs"
                        FlushInterval = 901
                        State         = "ReadWrite"
                    }
                    $results = Set-DbaDbQueryStoreOption @splatSetOptions
                    $results.DataFlushIntervalInSeconds | Should -Be 901
                }
            }
        }

        It "Should return only one database when specified" {
            foreach ($testResult in $allResults) {
                if ($testResult.Server.VersionMajor -ge 13) {
                    $results = Get-DbaDbQueryStoreOption -SqlInstance $testResult.Instance -Database "dbatoolsciqs"
                    $results.Status.Count | Should -Be 1
                    $results.Database | Should -Be "dbatoolsciqs"
                }
            }
        }

        It "Should exclude specified database" {
            foreach ($testResult in $allResults) {
                if ($testResult.Server.VersionMajor -ge 13) {
                    $results = Get-DbaDbQueryStoreOption -SqlInstance $testResult.Instance -ExcludeDatabase "dbatoolsciqs"
                    $excludedResult = $results | Where-Object Database -eq "dbatoolsciqs"
                    $excludedResult.Status.Count | Should -Be 0
                }
            }
        }
    }
}
