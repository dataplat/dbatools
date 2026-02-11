#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaKerberos",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should have SqlInstance in Instance parameter set" {
            $command = Get-Command $CommandName
            $instanceSet = $command.ParameterSets | Where-Object Name -eq "Instance"
            $instanceSet.Parameters.Name | Should -Contain "SqlInstance"
        }

        It "Should have ComputerName in Computer parameter set" {
            $command = Get-Command $CommandName
            $computerSet = $command.ParameterSets | Where-Object Name -eq "Computer"
            $computerSet.Parameters.Name | Should -Contain "ComputerName"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $result = Test-DbaKerberos -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @("ComputerName", "InstanceName", "Check", "Category", "Status", "Details", "Remediation")
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Returns multiple diagnostic checks" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result.Count | Should -BeGreaterThan 1 -Because "the command performs multiple diagnostic checks"
        }

        It "Has valid Status values" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $validStatuses = @("Pass", "Fail", "Warning")
            foreach ($item in $result) {
                $item.Status | Should -BeIn $validStatuses -Because "Status should be Pass, Fail, or Warning"
            }
        }

        It "Has valid Category values" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $validCategories = @("SPN", "Time Sync", "DNS", "Service Account", "Authentication", "Network", "Security Policy", "SQL Configuration", "Client")
            foreach ($item in $result) {
                $item.Category | Should -BeIn $validCategories -Because "Category should be one of the documented categories"
            }
        }
    }
}
