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

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $result = Enable-DbaTraceFlag -SqlInstance $testInstance -TraceFlag $safeTraceFlag -EnableException
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'SourceServer',
                'InstanceName',
                'SqlInstance',
                'TraceFlag',
                'Status',
                'Notes',
                'DateTime'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}