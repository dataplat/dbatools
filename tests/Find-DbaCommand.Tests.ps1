#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaCommand",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Pattern",
                "Tag",
                "Author",
                "MinimumVersion",
                "MaximumVersion",
                "Rebuild",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command finds jobs using all parameters" {
        It "Should find more than 5 snapshot commands" {
            $results = @(Find-DbaCommand -Pattern "snapshot")
            $results.Count | Should -BeGreaterThan 5
        }

        It "Should find more than 20 commands tagged as job" {
            $results = @(Find-DbaCommand -Tag Job)
            $results.Count | Should -BeGreaterThan 20
        }

        It "Should find a command that has both Job and Owner tags" {
            $results = @(Find-DbaCommand -Tag Job, Owner)
            $results.CommandName | Should -Contain "Test-DbaAgentJobOwner"
        }

        It "Should find more than 250 commands authored by Chrissy" {
            $results = @(Find-DbaCommand -Author chrissy)
            $results.Count | Should -BeGreaterThan 250
        }

        It "Should find more than 15 commands for AGs authored by Chrissy" {
            $results = @(Find-DbaCommand -Author chrissy -Tag AG)
            $results.Count | Should -BeGreaterThan 15
        }

        It "Should find more than 5 snapshot commands after Rebuilding the index" {
            $results = @(Find-DbaCommand -Pattern snapshot -Rebuild)
            $results.Count | Should -BeGreaterThan 5
        }
    }
}