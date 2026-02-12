#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaQueryExecutionTime",
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
                "Database",
                "ExcludeDatabase",
                "MaxResultsPerDb",
                "MinExecs",
                "MinExecMs",
                "ExcludeSystem",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaQueryExecutionTime -SqlInstance $TestConfig.InstanceSingle -MinExecs 1 -MinExecMs 0 -MaxResultsPerDb 1
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ProcName",
                "ObjectID",
                "TypeDesc",
                "Executions",
                "AvgExecMs",
                "MaxExecMs",
                "CachedTime",
                "LastExecTime",
                "TotalWorkerTimeMs",
                "TotalElapsedTimeMs",
                "SQLText"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has FullStatementText excluded from default display" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "FullStatementText" -Because "FullStatementText should be excluded from default display"
        }

        It "Has FullStatementText available as a property" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].PSObject.Properties.Name | Should -Contain "FullStatementText"
        }
    }
}