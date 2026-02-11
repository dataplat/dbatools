#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaTraceFlag",
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

        # Explain what needs to be set up for the test:
        # To test disabling trace flags, we need to ensure a trace flag is enabled first.
        # We use trace flag 3226 which is safe for testing as it only suppresses backup success messages.

        # Set variables. They are available in all the It blocks.
        $safeTraceFlag = 3226
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $startingTraceFlags = Get-DbaTraceFlag -SqlInstance $server

        # Create the objects.
        if ($startingTraceFlags.TraceFlag -notcontains $safeTraceFlag) {
            $null = $server.Query("DBCC TRACEON($safeTraceFlag,-1)")
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        if ($startingTraceFlags.TraceFlag -contains $safeTraceFlag) {
            $server.Query("DBCC TRACEON($safeTraceFlag,-1) WITH NO_INFOMSGS")
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When disabling trace flags" {
        It "Should disable trace flag $safeTraceFlag" {
            $disableResults = Disable-DbaTraceFlag -SqlInstance $server -TraceFlag $safeTraceFlag
            $disableResults.TraceFlag | Should -Contain $safeTraceFlag
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Re-enable the trace flag so we can disable it and capture a result
            $outputServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = $outputServer.Query("DBCC TRACEON($safeTraceFlag,-1)")
            $outputAll = @(Disable-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle -TraceFlag $safeTraceFlag)
            $outputResult = $outputAll | Where-Object { $null -ne $PSItem }
        }

        It "Returns output as PSCustomObject" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProperties = @("SourceServer", "InstanceName", "SqlInstance", "TraceFlag", "Status", "Notes", "DateTime")
            foreach ($prop in $expectedProperties) {
                $outputResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has a Status of Successful" {
            $outputResult[0].Status | Should -Be "Successful"
        }

        It "Has a DateTime value" {
            $outputResult[0].DateTime | Should -Not -BeNullOrEmpty
        }
    }
}