#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXEObject",
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
                "Type",
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
    # CHARACTERIZATION (TA-132): Get-DbaXEObject has NO connection-independent guard - it connects
    # (Connect-DbaInstance -MinimumVersion 9) as its first action and enumerates sys.dm_xe_packages /
    # sys.dm_xe_objects, so the whole behavior rides the standalone gate against InstanceSingle. These
    # pins record the current shape: a populated result set, the documented default-view members, and
    # that -Type narrows the result to a single ObjectType. Exact counts are intentionally NOT pinned
    # (they vary by SQL Server version/edition); only that the sets are populated and correctly typed.
    Context "Verifying command output" {
        BeforeAll {
            $results = Get-DbaXEObject -SqlInstance $TestConfig.InstanceSingle
        }

        It "returns Extended Events objects from the instance" {
            $results.Count | Should -BeGreaterThan 1
        }

        It "surfaces the documented output properties" {
            $first = $results | Select-Object -First 1
            $first.PSObject.Properties.Name | Should -Contain "PackageName"
            $first.PSObject.Properties.Name | Should -Contain "ObjectType"
            $first.PSObject.Properties.Name | Should -Contain "TargetName"
            $first.PSObject.Properties.Name | Should -Contain "Description"
        }

        It "narrows the result to a single ObjectType when -Type is supplied" {
            $events = Get-DbaXEObject -SqlInstance $TestConfig.InstanceSingle -Type Event
            $events.Count | Should -BeGreaterThan 1
            ($events.ObjectType | Sort-Object -Unique) | Should -Be "Event"
        }
    }
}
