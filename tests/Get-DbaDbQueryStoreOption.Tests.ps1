#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbQueryStoreOption",
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

        # Set variables. They are available in all the It blocks.
        $testDbName = "dbatoolsci_qso_$(Get-Random)"

        # Create a test database for query store testing
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $testDbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "When retrieving Query Store options" {
        BeforeAll {
            $results = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $testDbName -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return the correct database" {
            $results.Database | Should -Be $testDbName
        }

        It "Should have a valid ActualState" {
            $results.ActualState | Should -BeIn "Off", "ReadWrite", "ReadOnly", "Error"
        }

        It "Should have a valid MaxStorageSizeInMB" {
            $results.MaxStorageSizeInMB | Should -BeGreaterThan 0
        }
    }

    Context "Output validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.QueryStoreOptions]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ActualState",
                "DataFlushIntervalInSeconds",
                "StatisticsCollectionIntervalInMinutes",
                "MaxStorageSizeInMB",
                "CurrentStorageSizeInMB",
                "QueryCaptureMode",
                "SizeBasedCleanupMode",
                "StaleQueryThresholdInDays"
            )
            if ($server.VersionMajor -ge 14) {
                $expectedColumns += @(
                    "MaxPlansPerQuery",
                    "WaitStatsCaptureMode"
                )
            }
            if ($server.VersionMajor -ge 15) {
                $expectedColumns += @(
                    "CustomCapturePolicyExecutionCount",
                    "CustomCapturePolicyTotalCompileCPUTimeMS",
                    "CustomCapturePolicyTotalExecutionCPUTimeMS",
                    "CustomCapturePolicyStaleThresholdHours"
                )
            }
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.QueryStoreOptions"
        }
    }
}