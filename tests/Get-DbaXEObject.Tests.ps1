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
    BeforeDiscovery {
        $typeCases = @(
            @{ TypeName = "Event" }
            @{ TypeName = "Action" }
            @{ TypeName = "Target" }
            @{ TypeName = "PredicateComparator" }
            @{ TypeName = "PredicateSource" }
        )
    }

    Context "When no type is given" {
        BeforeAll {
            $resultsAll = @(Get-DbaXEObject -SqlInstance $TestConfig.InstanceSingle -WarningVariable warnAll)
        }

        It "Returns the objects of every type without a warning" {
            $warnAll | Should -BeNullOrEmpty
            $resultsAll.ObjectType | Should -Contain "Event"
            $resultsAll.ObjectType | Should -Contain "PredicateComparator"
        }
    }

    Context "When a type is given" {
        It "Returns only objects of type <TypeName>, and some of them" -ForEach $typeCases {
            # The two predicate types matched nothing until #10600, because the translation to the raw names
            # pred_compare and pred_source was discarded.
            $resultsType = @(Get-DbaXEObject -SqlInstance $TestConfig.InstanceSingle -Type $TypeName -WarningVariable warnType)
            $warnType | Should -BeNullOrEmpty
            $resultsType.Count | Should -BeGreaterThan 0
            $resultsType.ObjectType | Select-Object -Unique | Should -Be $TypeName
        }

        It "Returns nothing but XE objects" {
            # The discarded translation used to be written to the output as two strings per call.
            $resultsMixed = @(Get-DbaXEObject -SqlInstance $TestConfig.InstanceSingle -Type Event, PredicateSource)
            $resultsMixed | Where-Object { $PSItem -is [string] } | Should -BeNullOrEmpty
            ($resultsMixed.ObjectType | Select-Object -Unique | Sort-Object) | Should -Be @("Event", "PredicateSource")
        }
    }
}