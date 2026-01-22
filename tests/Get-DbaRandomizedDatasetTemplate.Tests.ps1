#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRandomizedDatasetTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Template",
                "Path",
                "ExcludeDefault",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns templates" {
        It "Should have at least 1 row" {
            $templates = @(Get-DbaRandomizedDatasetTemplate)
            $templates.Count | Should -BeGreaterThan 0
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaRandomizedDatasetTemplate -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "BaseName",
                "FullName"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output Validation with -Path" {
        BeforeAll {
            # Create a temporary directory with a test template
            $tempPath = Join-Path $env:TEMP "DbaRandomizedDatasetTemplateTest"
            if (-not (Test-Path $tempPath)) {
                New-Item -Path $tempPath -ItemType Directory | Out-Null
            }
            $testTemplate = @{
                Name    = "Test"
                Columns = @()
            } | ConvertTo-Json
            $testTemplate | Out-File -FilePath "$tempPath\TestTemplate.json" -Encoding utf8
            
            $result = Get-DbaRandomizedDatasetTemplate -Path $tempPath -EnableException
        }

        AfterAll {
            # Clean up temporary directory
            if (Test-Path $tempPath) {
                Remove-Item -Path $tempPath -Recurse -Force
            }
        }

        It "Returns templates from custom path with same properties" {
            $result.PSObject.Properties.Name | Should -Contain "BaseName"
            $result.PSObject.Properties.Name | Should -Contain "FullName"
        }
    }

    Context "Output Validation with -ExcludeDefault" {
        BeforeAll {
            # Create a temporary directory with a test template
            $tempPath = Join-Path $env:TEMP "DbaRandomizedDatasetTemplateTest2"
            if (-not (Test-Path $tempPath)) {
                New-Item -Path $tempPath -ItemType Directory | Out-Null
            }
            $testTemplate = @{
                Name    = "Test"
                Columns = @()
            } | ConvertTo-Json
            $testTemplate | Out-File -FilePath "$tempPath\CustomTemplate.json" -Encoding utf8
            
            $result = Get-DbaRandomizedDatasetTemplate -Path $tempPath -ExcludeDefault -EnableException
        }

        AfterAll {
            # Clean up temporary directory
            if (Test-Path $tempPath) {
                Remove-Item -Path $tempPath -Recurse -Force
            }
        }

        It "Returns only custom templates when -ExcludeDefault is specified" {
            $result | Should -Not -BeNullOrEmpty
            $result.BaseName | Should -Be "CustomTemplate"
        }
    }
}