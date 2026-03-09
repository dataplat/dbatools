#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaEndpoint",
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
                "Endpoint",
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When connecting to SQL Server" {
        It "gets some endpoints" {
            $results = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle)
            $results.Count | Should -BeGreaterThan 1
            $results.Name | Should -Contain "TSQL Default TCP"
        }

        It "gets one endpoint" {
            $results = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint "TSQL Default TCP")
            $results.Name | Should -Be "TSQL Default TCP"
            $results.Count | Should -Be 1
        }
    }
}