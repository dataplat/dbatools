#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXEStore",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    # CHARACTERIZATION (TA-133): Get-DbaXEStore has NO connection-independent guard - it connects
    # (Connect-DbaInstance -MinimumVersion 11) as its first action and constructs an XEStore over the
    # live connection, so the whole behavior rides the standalone gate against InstanceSingle. These
    # pins record the current shape: one XEStore object per instance, the documented default-view
    # members, and that the Sessions/Packages collections are populated (system_health always exists on
    # SQL Server 2008+). Exact counts are intentionally NOT pinned (they vary by version/edition).
    Context "Verifying command output" {
        BeforeAll {
            $results = Get-DbaXEStore -SqlInstance $TestConfig.InstanceSingle
        }

        It "returns exactly one Extended Events store for the instance" {
            @($results).Count | Should -Be 1
        }

        It "returns an XEStore object" {
            $results.GetType().Name | Should -Be "XEStore"
        }

        It "surfaces the documented default-view members" {
            $memberNames = $results.PSObject.Properties.Name
            $memberNames | Should -Contain "ComputerName"
            $memberNames | Should -Contain "InstanceName"
            $memberNames | Should -Contain "SqlInstance"
            $memberNames | Should -Contain "ServerName"
            $memberNames | Should -Contain "Sessions"
            $memberNames | Should -Contain "Packages"
            $memberNames | Should -Contain "RunningSessionCount"
        }

        It "exposes populated Sessions and Packages collections" {
            $results.Sessions.Count | Should -BeGreaterThan 0
            $results.Packages.Count | Should -BeGreaterThan 0
        }

        It "accepts the instance from the pipeline" {
            $piped = $TestConfig.InstanceSingle | Get-DbaXEStore
            $piped.GetType().Name | Should -Be "XEStore"
        }
    }
}