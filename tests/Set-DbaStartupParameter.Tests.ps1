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
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $global:defaultInstance = $TestConfig.instance1
        $global:namedInstance = $TestConfig.instance2
        $global:SkipLocalTest = $true # Change to $false to run the tests on a local instance.

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate command functionality" {
        # See https://github.com/dataplat/dbatools/issues/7035
        It -Skip:$global:SkipLocalTest "Ensure the startup params are not duplicated when more than one server is modified in the same invocation" {
            $splatSetStartup = @{
                SqlInstance = $global:defaultInstance, $global:namedInstance
                TraceFlag   = 3226
                Confirm     = $false
            }
            $result = Set-DbaStartupParameter @splatSetStartup

            $resultDefaultInstance = Get-DbaStartupParameter -SqlInstance $global:defaultInstance
            $resultDefaultInstance.TraceFlags.Count | Should -Be 1
            $resultDefaultInstance.TraceFlags[0] | Should -Be 3226

            # The duplication occurs after the first server is processed.
            $resultNamedInstance = Get-DbaStartupParameter -SqlInstance $global:namedInstance
            # Using the defaults to test locally
            $resultNamedInstance.MasterData.Count | Should -Be 1
            $resultNamedInstance.MasterLog.Count | Should -Be 1
            $resultNamedInstance.ErrorLog.Count | Should -Be 1

            $resultNamedInstance.TraceFlags.Count | Should -Be 1
            $resultNamedInstance.TraceFlags[0] | Should -Be 3226
        }

        # See https://github.com/dataplat/dbatools/issues/7035
        It -Skip:$global:SkipLocalTest "Ensure the correct instance name is returned" {
            $splatSetInstance = @{
                SqlInstance = $global:namedInstance
                TraceFlag   = 3226
                Confirm     = $false
            }
            $result = Set-DbaStartupParameter @splatSetInstance

            $result.SqlInstance | Should -Be $global:namedInstance
            $result.TraceFlags.Count | Should -Be 1
            $result.TraceFlags[0] | Should -Be 3226
        }
    }
}