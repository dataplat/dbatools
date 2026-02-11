#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTraceFlag",
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
    Context "Verifying TraceFlag output" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $safeTraceFlag = 3226
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $startingTfs = @( $server.Query("DBCC TRACESTATUS(-1)") )
            $startingTfsCount = $startingTfs.Count

            if ($startingTfs.TraceFlag -notcontains $safeTraceFlag) {
                $server.Query("DBCC TRACEON($safeTraceFlag,-1) WITH NO_INFOMSGS")
                $startingTfsCount++
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($startingTfs.TraceFlag -notcontains $safeTraceFlag) {
                $server.Query("DBCC TRACEOFF($safeTraceFlag,-1)")
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Has the right default properties" {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "TraceFlag", "Global", "Status"
            $results = @( )
            $results += Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Returns filtered results" {
            $results = Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle -TraceFlag $safeTraceFlag
            $results.TraceFlag.Count | Should -Be 1
            $results.TraceFlag | Should -Be $safeTraceFlag
            $results.Status | Should -Be 1
        }

        It "Returns all TFs" {
            $results = Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle
            #$results.TraceFlag.Count | Should -Be $startingTfsCount
            $results.TraceFlag | Should -Be $safeTraceFlag
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputSafeTraceFlag = 3226
            $outputServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $outputStartingTfs = @($outputServer.Query("DBCC TRACESTATUS(-1)"))
            if ($outputStartingTfs.TraceFlag -notcontains $outputSafeTraceFlag) {
                $outputServer.Query("DBCC TRACEON($outputSafeTraceFlag,-1) WITH NO_INFOMSGS")
                $global:outputTfWasEnabled = $true
            }
            $result = Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle
        }

        AfterAll {
            if ($global:outputTfWasEnabled) {
                $outputServer.Query("DBCC TRACEOFF($outputSafeTraceFlag,-1)")
                $global:outputTfWasEnabled = $false
            }
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "TraceFlag", "Global", "Status")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Does not include excluded properties in default display" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "Session" -Because "Session is excluded via Select-DefaultView"
        }

        It "Has the Session property available" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].PSObject.Properties.Name | Should -Contain "Session" -Because "Session should be accessible via Select-Object *"
        }
    }
}