#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaFilestream",
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
                "FileStreamLevel",
                "ShareName",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Get-FilestreamReturnValue translates the WMI return value" {
        # The clause for the success codes used to read { 2147021885 -or 2147945411 -or 0 }, a
        # constant expression that is always true, so it matched every code. Since switch runs
        # every matching clause, a documented refusal came back as its own message *and* the
        # success message, and an unrecognized code never reached default and was reported as a
        # plain success. Enable-DbaFilestream then discarded even that, so a refused call looked
        # like a successful one that had simply not taken effect yet.

        It "reports a documented refusal as a failure, with only its own message" {
            InModuleScope dbatools {
                $result = Get-FilestreamReturnValue -Value 2147024891

                $result.Category | Should -Be "Failure"
                $result.Message | Should -Be "Access denied"
                @($result.Message).Count | Should -Be 1
            }
        }

        It "reports the success codes as a success" {
            InModuleScope dbatools {
                (Get-FilestreamReturnValue -Value 0).Category | Should -Be "Success"
                (Get-FilestreamReturnValue -Value 2147021885).Category | Should -Be "Success"
                (Get-FilestreamReturnValue -Value 2147945411).Category | Should -Be "Success"
            }
        }

        It "reports an unrecognized code as unknown and keeps the raw value" {
            InModuleScope dbatools {
                $result = Get-FilestreamReturnValue -Value 99999

                $result.Category | Should -Be "Unknown"
                $result.ReturnValue | Should -Be 99999
                $result.Message | Should -BeLike "*99999*"
            }
        }

        It "reports a missing return value as unknown rather than as a success" {
            InModuleScope dbatools {
                (Get-FilestreamReturnValue -Value $null).Category | Should -Be "Unknown"
            }
        }

        It "matches the return value whatever numeric type the provider used" {
            # Invoke-CimMethod hands back a UInt32, so a switch that only matched Int32 would send
            # every real call down the unknown path.
            InModuleScope dbatools {
                (Get-FilestreamReturnValue -Value ([uint32]2147024891)).Category | Should -Be "Failure"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Disable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When changing FileStream Level" {
        It "Should change the FileStream Level to 1" {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -Force

            $results.InstanceAccessLevel | Should -Be 1
            $results.ServiceAccessLevel | Should -Be 1
        }

        It "Should change the FileStream Level to 2" -Skip:$env:APPVEYOR {
            # Skip this test on AppVeyor because the instance does not support FileStream Level 2.
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 2 -ShareName TestShare -Force

            $results.InstanceAccessLevel | Should -Be 2
            $results.ServiceAccessLevel | Should -Be 2
            $results.ServiceShareName | Should -Be TestShare
        }

        It "Should warn if using ShareName with FileStreamLevel 1" {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -ShareName Test -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike '*Filestream must be at least level 2 when using ShareName*'
            $results | Should -BeNullOrEmpty
        }
    }
}