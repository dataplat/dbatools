#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXESessionTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Pattern",
                "Template",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Get Template Index" {
        It "returns good results with no missing information" {
            $results = Get-DbaXESessionTemplate
            $results | Where-Object Name -eq $null | Should -BeNullOrEmpty
            $results | Where-Object TemplateName -eq $null | Should -BeNullOrEmpty
            $results | Where-Object Description -eq $null | Should -BeNullOrEmpty
            $results | Where-Object Category -eq $null | Should -BeNullOrEmpty
        }
    }

    Context "Get Error Reported template" {
        BeforeAll {
            $errorReported = Get-DbaXESessionTemplate | Where-Object Name -eq "Error Reported"
        }

        It "should return the Error Reported template" {
            $errorReported | Should -Not -BeNullOrEmpty
        }

        It "should have the correct metadata" {
            $errorReported.Name | Should -Be "Error Reported"
            $errorReported.Category | Should -Be "System Monitoring"
            $errorReported.Description | Should -BeLike "*severity*"
            $errorReported.Source | Should -Be "Kevin Kline"
        }

        It "should have valid XML with error_reported event" {
            $errorReported.TemplateName | Should -Be "Error Reported"
        }
    }
}