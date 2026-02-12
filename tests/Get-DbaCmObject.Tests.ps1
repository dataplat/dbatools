#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaCmObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ClassName",
                "Query",
                "ComputerName",
                "Credential",
                "Namespace",
                "DoNotUse",
                "Force",
                "SilentlyContinue",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Returns proper information" {
        BeforeAll {
            $result = Get-DbaCmObject -ClassName Win32_TimeZone
        }

        It "Returns a bias that's an int" {
            (Get-DbaCmObject -ClassName Win32_TimeZone).Bias | Should -BeOfType [int]
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.Management.Infrastructure.CimInstance"
        }

        It "Has expected properties for Win32_TimeZone" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["Bias"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["Caption"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["StandardName"] | Should -Not -BeNullOrEmpty
        }
    }
}