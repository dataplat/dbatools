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
        BeforeAll {
            # Fixture hygiene (2026-07-17): lab instances accumulate residual trace flags (a
            # stray -T2544 rode both Multi fixtures) and this suite's count assertions assume
            # ZERO pre-existing flags. -TraceFlagOverride with no -TraceFlag removes all trace
            # flags; startup parameters are pending-config reads, so no restart is needed for
            # these assertions. Clear up front and leave clean after.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaStartupParameter -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -TraceFlagOverride -Confirm:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaStartupParameter -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -TraceFlagOverride -Confirm:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        # See https://github.com/dataplat/dbatools/issues/7035
        It "Ensure the startup params are not duplicated when more than one server is modified in the same invocation" {
            $splatSetStartup = @{
                SqlInstance = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
                TraceFlag   = 3226
            }
            $result = Set-DbaStartupParameter @splatSetStartup

            $result1 = Get-DbaStartupParameter -SqlInstance $TestConfig.InstanceMulti1
            $result1.TraceFlags.Count | Should -Be 1
            $result1.TraceFlags[0] | Should -Be 3226

            # The duplication occurs after the first server is processed.
            $result2 = Get-DbaStartupParameter -SqlInstance $TestConfig.InstanceMulti2
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
                SqlInstance = $TestConfig.InstanceMulti1
                TraceFlag   = 3226
            }
            $result = Set-DbaStartupParameter @splatSetInstance

            $result.SqlInstance | Should -Be $TestConfig.InstanceMulti1
            $result.TraceFlags.Count | Should -Be 1
            $result.TraceFlags[0] | Should -Be 3226
        }
    }
}