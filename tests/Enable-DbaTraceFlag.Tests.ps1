#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaTraceFlag",
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
                "TraceFlag",
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

        # Set variables for the test
        $testInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $safeTraceFlag = 3226
        $startingTraceFlags = Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle

        if ($startingTraceFlags.TraceFlag -contains $safeTraceFlag) {
            $testInstance.Query("DBCC TRACEOFF($safeTraceFlag,-1)")
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($startingTraceFlags.TraceFlag -notcontains $safeTraceFlag) {
            $testInstance.Query("DBCC TRACEOFF($safeTraceFlag,-1)")
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When enabling a trace flag" {
        BeforeAll {
            $enableResults = Enable-DbaTraceFlag -SqlInstance $testInstance -TraceFlag $safeTraceFlag
        }

        It "Should enable the specified trace flag" {
            $enableResults.TraceFlag -contains $safeTraceFlag | Should -BeTrue
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Use a different trace flag (4199) to avoid conflicts with the 3226 used in other tests
            $outputTraceFlag = 4199
            $outputInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $currentOutputFlags = Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle
            if ($currentOutputFlags.TraceFlag -contains $outputTraceFlag) {
                $null = $outputInstance.Query("DBCC TRACEOFF($outputTraceFlag,-1)")
            }
            $outputResult = @(Enable-DbaTraceFlag -SqlInstance $outputInstance -TraceFlag $outputTraceFlag) | Where-Object { $null -ne $PSItem -and $PSItem.psobject.Properties["Status"] }
        }

        AfterAll {
            if ($outputInstance) {
                try { $null = $outputInstance.Query("DBCC TRACEOFF($outputTraceFlag,-1)") } catch { }
            }
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $outputResult | Should -Not -BeNullOrEmpty
            $expectedProps = @("SourceServer", "InstanceName", "SqlInstance", "TraceFlag", "Status", "Notes", "DateTime")
            foreach ($prop in $expectedProps) {
                $outputResult[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the correct Status for a successful enable" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].Status | Should -Be "Successful"
        }

        It "Has a valid DateTime property" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].DateTime | Should -Not -BeNullOrEmpty
            $outputResult[0].DateTime | Should -BeOfType [DbaDateTime]
        }
    }
}