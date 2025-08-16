#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaXESmartTarget",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing XESmartTarget installer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $results = Install-DbaXESmartTarget -Force

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have installed XESmartTarget successfully" {
            $results.Installed | Should -BeTrue
        }

        It "Should have the correct name" {
            $results.Name | Should -Match arget
        }

        It "Should return the correct type" {
            $results.Type | Should -Not -BeNullOrEmpty
        }

        It "XESmartTarget executable should exist" {
            $xeSmartTargetExe = Join-Path $results.Path $results.Name
            Test-Path $xeSmartTargetExe | Should -BeTrue
        }

        It "Should install required DLL files" {
            # Check for files that should exist based on the command output
            $requiredFiles = @("Microsoft.Data.SqlClient.SNI.dll", "NLog.config")
            foreach ($file in $requiredFiles) {
                $filePath = Join-Path $results.Path $file
                Test-Path $filePath | Should -BeTrue
            }
        }

        It "Should be accessible via Get-XESmartTargetPath" {
            $xeSmartTargetPath = Get-XESmartTargetPath
            $xeSmartTargetPath | Should -Not -BeNullOrEmpty
            Test-Path $xeSmartTargetPath | Should -BeTrue
        }

        It "Should have XESmartTarget directory path matching cross-platform pattern" {
            # Test that the path contains the expected directory structure
            $results.Path | Should -Match "dbatools[/\\]xesmarttarget"
        }
    }
}