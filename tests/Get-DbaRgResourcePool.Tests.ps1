#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRgResourcePool",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting resource pools" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $allResults = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets Results" {
            $allResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "When getting resource pools using -Type parameter" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $typeResults = Get-DbaRgResourcePool -SqlInstance $TestConfig.InstanceSingle -Type Internal
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets Results with Type filter" {
            $typeResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Multi-record pipe emits each pool exactly once (deviation from source)" {
        # The retired function accumulated instances in a process-scope `$InputObject +=`, so a
        # multi-record pipe re-emitted earlier records' pools: record 2 relisted record 1's pools,
        # giving 9 rows where 6 existed. The compiled port runs each pipeline record in its own hop
        # scope and emits every pool exactly once. This is the deviation from source,
        # and a single-instance leg cannot observe it - it needs at least two piped records.
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $instanceOne = $TestConfig.InstanceMulti1
            $instanceTwo = $TestConfig.InstanceMulti2
            $pipedResults = @($instanceOne, $instanceTwo | Get-DbaRgResourcePool)
            $expectedResults = @(Get-DbaRgResourcePool -SqlInstance $instanceOne) + @(Get-DbaRgResourcePool -SqlInstance $instanceTwo)
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "emits each instance's pools exactly once across a two-instance pipe" {
            $pipedResults.Count | Should -Be $expectedResults.Count
        }

        It "never re-emits an earlier record's pool" {
            $duplicated = $pipedResults | Group-Object -Property SqlInstance, Name | Where-Object Count -gt 1
            $duplicated | Should -BeNullOrEmpty
        }
    }
}