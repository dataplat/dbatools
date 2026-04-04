#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaInstanceList",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Register",
                "Scope"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $instanceName = "dbatoolsci_testinstance_$(Get-Random)"
        Add-DbaInstanceList -SqlInstance $instanceName
    }

    Context "removes instances from the list" {
        It "removes an instance without error" {
            { Remove-DbaInstanceList -SqlInstance $instanceName -Confirm:$false } | Should -Not -Throw
        }

        It "instance no longer appears in Get-DbaInstanceList after removal" {
            $result = Get-DbaInstanceList
            $result | Should -Not -Contain $instanceName.ToLowerInvariant()
        }
    }
}
