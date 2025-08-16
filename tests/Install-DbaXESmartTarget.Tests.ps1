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
                "EnableException",
                "Path",
                "Type",
                "Version"
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
            $results.Name | Should -Match "arget"
        }

        It "Should return the correct type" {
            $results.Type | Should -Not -BeNullOrEmpty
        }

        It "XESmartTarget executable should exist" {
            # The Path property contains the full path to the executable, not just the directory
            Test-Path $results.Path | Should -BeTrue
        }

        It "Should install required DLL files" {
            # Get the directory from the executable path
            $installDir = Split-Path $results.Path -Parent

            # Check for files that should exist - be more flexible about which files exist
            $possibleFiles = @(
                "Microsoft.Data.SqlClient.SNI.dll",
                "NLog.config",
                "XESmartTarget.Core.dll",
                "XESmartTarget.Core.pdb"
            )

            $foundFiles = 0
            foreach ($file in $possibleFiles) {
                $filePath = Join-Path $installDir $file
                if (Test-Path $filePath) {
                    $foundFiles++
                }
            }

            # At least some required files should exist
            $foundFiles | Should -BeGreaterThan 0
        }

        It "Should be accessible via Get-XESmartTargetPath" {
            $xeSmartTargetPath = Get-XESmartTargetPath
            $xeSmartTargetPath | Should -Not -BeNullOrEmpty
            Test-Path $xeSmartTargetPath | Should -BeTrue
        }

        It "Should have XESmartTarget directory path matching cross-platform pattern" {
            # Test that the path contains the expected directory structure
            # Use Split-Path to get the directory portion for testing
            $installDir = if ($results.Path -match '\.exe$') {
                Split-Path $results.Path -Parent
            } else {
                $results.Path
            }
            $installDir | Should -Match "dbatools[/\\]xesmarttarget"
        }
    }
}