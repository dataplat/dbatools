#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaXEFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Raw",
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

        # Get the system_health session for testing
        $xeSession = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command output" {
        BeforeAll {
            $allDefault = @($xeSession | Read-DbaXEFile)
            $resultDefault = @($allDefault | Select-Object -First 3)
            $allRaw = @($xeSession | Read-DbaXEFile -Raw)
            $resultRaw = @($allRaw | Select-Object -First 3)
        }

        It "returns some results with Raw parameter" {
            $allRaw | Should -Not -BeNullOrEmpty
        }

        It "returns some results without Raw parameter" {
            $allDefault | Should -Not -BeNullOrEmpty
        }

        It "Returns PSCustomObject by default" {
            if (-not $resultDefault) { Set-ItResult -Skipped -Because "no result to validate" }
            $resultDefault[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the standard name and timestamp properties" {
            if (-not $resultDefault) { Set-ItResult -Skipped -Because "no result to validate" }
            $resultDefault[0].PSObject.Properties.Name | Should -Contain "name"
            $resultDefault[0].PSObject.Properties.Name | Should -Contain "timestamp"
        }

        It "Returns XEvent objects when using -Raw" {
            if (-not $resultRaw) { Set-ItResult -Skipped -Because "no result to validate" }
            $resultRaw[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.XEvent.XELite.XEvent"
        }
    }
}