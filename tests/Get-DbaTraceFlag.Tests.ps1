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
            # -Contain, not -Be: an unfiltered call returns every global trace flag on the
            # instance, so -Be asserted that the one this suite enables is the ONLY one. Lab
            # instances accumulate residual startup flags (a stray -T2544 is on this one, and
            # Set-DbaStartupParameter.Tests.ps1 clears the same flag off the Multi fixtures for
            # the same reason), and a startup flag returns after every restart, so clearing it
            # here would neither hold nor be safe on an instance other suites share. What this
            # test is for is that the unfiltered call includes the flag we turned on; the
            # filtered case is already pinned to exactly one result above.
            $results.TraceFlag | Should -Contain $safeTraceFlag
        }
    }
}