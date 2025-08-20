#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaErrorLogConfig",
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
                "LogCount",
                "LogSize",
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

        # Store original values for cleanup
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $originalLogFiles2 = $server2.NumberOfLogFiles
        $originalLogSize2 = $server2.ErrorLogSizeKb

        $server2.NumberOfLogFiles = 4
        $server2.ErrorLogSizeKb = 1024
        $server2.Alter()

        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $originalLogFiles1 = $server1.NumberOfLogFiles
        $originalLogSize1 = $server1.ErrorLogSizeKb

        $server1.NumberOfLogFiles = 4
        $server1.Alter()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Restore original settings
        $cleanupServer1 = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $cleanupServer1.NumberOfLogFiles = $originalLogFiles1
        $cleanupServer1.ErrorLogSizeKb = $originalLogSize1
        $cleanupServer1.Alter()

        $cleanupServer2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $cleanupServer2.NumberOfLogFiles = $originalLogFiles2
        $cleanupServer2.ErrorLogSizeKb = $originalLogSize2
        $cleanupServer2.Alter()
    }

    Context "Apply LogCount to multiple instances" {
        BeforeAll {
            $logCountResults = Set-DbaErrorLogConfig -SqlInstance $TestConfig.instance2, $TestConfig.instance1 -LogCount 8
        }

        It "Returns LogCount set to 8 for each instance" {
            foreach ($result in $logCountResults) {
                $result.LogCount | Should -Be 8
            }
        }
    }
    Context "Apply LogSize to multiple instances" {
        BeforeAll {
            $logSizeResults = Set-DbaErrorLogConfig -SqlInstance $TestConfig.instance2, $TestConfig.instance1 -LogSize 100 -WarningAction SilentlyContinue -WarningVariable warn2
        }

        It "Returns LogSize set to 100 for each instance" {
            foreach ($result in $logSizeResults) {
                $result.LogSize.Kilobyte | Should -Be 100
            }
        }
    }
}