#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaManagementObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "VersionNumber",
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
    BeforeAll {
        $results = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME
        $versionResults = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME -VersionNumber 17
    }

    It "returns results" {
        $results | Should -Not -BeNullOrEmpty
    }

    It "Returns the version specified" {
        $versionResults | Should -Not -BeNullOrEmpty
    }

    Context "Output validation" {
        It "Returns output of the expected type" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("ComputerName", "Version", "Loaded", "Path", "LoadTemplate")
            foreach ($prop in $expectedProps) {
                $results[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}