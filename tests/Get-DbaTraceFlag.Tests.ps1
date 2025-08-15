#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTraceFlag",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

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

            $global:safeTraceFlag = 3226
            $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $global:startingTfs = $global:server.Query("DBCC TRACESTATUS(-1)")
            $global:startingTfsCount = $global:startingTfs.Count

            if ($global:startingTfs.TraceFlag -notcontains $global:safeTraceFlag) {
                $global:server.Query("DBCC TRACEON($global:safeTraceFlag,-1) WITH NO_INFOMSGS")
                $global:startingTfsCount++
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($global:startingTfs.TraceFlag -notcontains $global:safeTraceFlag) {
                $global:server.Query("DBCC TRACEOFF($global:safeTraceFlag,-1)")
            }
        }

        It "Has the right default properties" {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "TraceFlag", "Global", "Status"
            $results = Get-DbaTraceFlag -SqlInstance $TestConfig.instance2
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Returns filtered results" {
            $results = Get-DbaTraceFlag -SqlInstance $TestConfig.instance2 -TraceFlag $global:safeTraceFlag
            $results.TraceFlag.Count | Should -Be 1
        }

        It "Returns following number of TFs: $($global:startingTfsCount)" {
            $results = Get-DbaTraceFlag -SqlInstance $TestConfig.instance2
            $results.TraceFlag.Count | Should -Be $global:startingTfsCount
        }
    }
}