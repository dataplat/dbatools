#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaXESessionTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Destination",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When copying XE session templates" {
        BeforeAll {
            # Clean up any existing copied templates for a clean test
            $templatePath = "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates"

            # Get the source template name for later validation
            $sourceTemplate = (Get-DbaXESessionTemplate | Where-Object Source -ne "Microsoft").Path | Select-Object -First 1
            if ($sourceTemplate) {
                $sourceTemplateName = $sourceTemplate.Name
            }
        }

        AfterAll {
            # Clean up test artifacts if needed
            # We don't remove the templates as they might be useful for the user
        }

        It "Successfully copies the template files" {
            $null = Copy-DbaXESessionTemplate *>&1
            $templatePath = "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates"

            if ($sourceTemplateName) {
                $copiedTemplate = Get-ChildItem -Path $templatePath | Where-Object Name -eq $sourceTemplateName
                $copiedTemplate | Should -Not -BeNullOrEmpty
            }
        }
    }
}