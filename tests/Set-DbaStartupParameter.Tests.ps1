#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaStartupParameter",
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
                "Credential",
                "MasterData",
                "MasterLog",
                "ErrorLog",
                "TraceFlag",
                "CommandPromptStart",
                "MinimalStart",
                "MemoryToReserve",
                "SingleUser",
                "SingleUserDetails",
                "NoLoggingToWinEvents",
                "StartAsNamedInstance",
                "DisableMonitoring",
                "IncreasedExtents",
                "TraceFlagOverride",
                "StartupConfig",
                "Offline",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Validate command functionality" {
        # See https://github.com/dataplat/dbatools/issues/7035
        It "Ensure the startup params are not duplicated when more than one server is modified in the same invocation" {
            $splatSetStartup = @{
                SqlInstance = $TestConfig.instanceMulti1, $TestConfig.instanceMulti2
                TraceFlag   = 3226
            }
            $result = Set-DbaStartupParameter @splatSetStartup

            $result1 = Get-DbaStartupParameter -SqlInstance $TestConfig.instanceMulti1
            $result1.TraceFlags.Count | Should -Be 1
            $result1.TraceFlags[0] | Should -Be 3226

            # The duplication occurs after the first server is processed.
            $result2 = Get-DbaStartupParameter -SqlInstance $TestConfig.instanceMulti2
            # Using the defaults to test locally
            $result2.MasterData.Count | Should -Be 1
            $result2.MasterLog.Count | Should -Be 1
            $result2.ErrorLog.Count | Should -Be 1

            $result2.TraceFlags.Count | Should -Be 1
            $result2.TraceFlags[0] | Should -Be 3226
        }

        # See https://github.com/dataplat/dbatools/issues/7035
        It "Ensure the correct instance name is returned" {
            $splatSetInstance = @{
                SqlInstance = $TestConfig.instanceMulti1
                TraceFlag   = 3226
            }
            $result = Set-DbaStartupParameter @splatSetInstance

            $result.SqlInstance | Should -Be $TestConfig.instanceMulti1
            $result.TraceFlags.Count | Should -Be 1
            $result.TraceFlags[0] | Should -Be 3226
        }
    }
}