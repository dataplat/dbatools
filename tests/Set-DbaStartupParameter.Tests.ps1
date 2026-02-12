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
    Context "Validate command functionality" -Skip:(-not $TestConfig.InstanceMulti1) {
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

        Context "Output validation" {
            BeforeAll {
                if ($TestConfig.InstanceSingle) {
                    $splatOutputTest = @{
                        SqlInstance = $TestConfig.InstanceSingle
                        TraceFlag   = 3226
                        Confirm     = $false
                    }
                    $script:outputForValidation = Set-DbaStartupParameter @splatOutputTest
                }
            }

            It "Returns output of the expected type" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $script:outputForValidation | Should -Not -BeNullOrEmpty
                $script:outputForValidation | Should -BeOfType PSCustomObject
            }

            It "Has the expected base properties from Get-DbaStartupParameter" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $expectedProps = @(
                    "ComputerName",
                    "InstanceName",
                    "SqlInstance",
                    "MasterData",
                    "MasterLog",
                    "ErrorLog",
                    "TraceFlags",
                    "DebugFlags",
                    "CommandPromptStart",
                    "MinimalStart",
                    "MemoryToReserve",
                    "SingleUser",
                    "SingleUserName",
                    "NoLoggingToWinEvents",
                    "StartAsNamedInstance",
                    "DisableMonitoring",
                    "IncreasedExtents",
                    "ParameterString"
                )
                foreach ($prop in $expectedProps) {
                    $script:outputForValidation.psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
                }
            }

            It "Has the added OriginalStartupParameters NoteProperty" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $script:outputForValidation.psobject.Properties["OriginalStartupParameters"] | Should -Not -BeNullOrEmpty
                $script:outputForValidation.psobject.Properties["OriginalStartupParameters"].MemberType | Should -Be "NoteProperty"
            }

            It "Has the added Notes NoteProperty" {
                if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "no result to validate" }
                $script:outputForValidation.psobject.Properties["Notes"] | Should -Not -BeNullOrEmpty
                $script:outputForValidation.psobject.Properties["Notes"].MemberType | Should -Be "NoteProperty"
                $script:outputForValidation.Notes | Should -Match "restart"
            }
        }
    }
}