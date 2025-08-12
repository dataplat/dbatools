#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Install-DbaSqlPackage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Method",
                "Force",
                "Version",
                "Scope",
                "InstallPath",
                "AddToPath",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing SqlPackage installation with Zip method" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a temporary install path for testing
            $tempInstallPath = Join-Path ([System.IO.Path]::GetTempPath()) "SqlPackageTest_$(Get-Random)"

            # Remove any existing sqlpackage from PATH for clean test
            $existingSqlPackage = Get-Command sqlpackage -ErrorAction SilentlyContinue
            if ($existingSqlPackage) {
                Write-Host "Found existing SqlPackage at: $($existingSqlPackage.Source)" -ForegroundColor Yellow
            }

            $resultsZip = Install-DbaSqlPackage -Method Zip -InstallPath $tempInstallPath -Force -Verbose:$false

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up test installation
            if (Test-Path $tempInstallPath) {
                Remove-Item $tempInstallPath -Recurse -Force
            }

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "Installs to specified path: $tempInstallPath" {
            $resultsZip.InstallPath | Should -Be $tempInstallPath
        }

        It "Shows status of Successfully Installed" {
            $resultsZip.Status | Should -Be "Successfully Installed"
        }

        It "Uses Zip method" {
            $resultsZip.Method | Should -Be "Zip"
        }

        It "Has the correct properties" {
            $result = $resultsZip
            $ExpectedProps = "Status", "Path", "Version", "Method", "InstallPath"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Creates SqlPackage executable in install path" {
            $isWindows = if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWindows } else { $env:OS -eq "Windows_NT" }
            $executableName = if ($isWindows) { "SqlPackage.exe" } else { "sqlpackage" }
            $executablePath = Join-Path $tempInstallPath $executableName
            Test-Path $executablePath | Should -Be $true
        }
    }

    Context "Testing SqlPackage installation with Auto method" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a temporary install path for testing
            $tempInstallPathAuto = Join-Path ([System.IO.Path]::GetTempPath()) "SqlPackageTestAuto_$(Get-Random)"

            $resultsAuto = Install-DbaSqlPackage -Method Auto -InstallPath $tempInstallPathAuto -Force -Verbose:$false

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up test installation
            if (Test-Path $tempInstallPathAuto) {
                Remove-Item $tempInstallPathAuto -Recurse -Force
            }

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "Auto method defaults to Zip" {
            $resultsAuto.Method | Should -Be "Zip"
        }

        It "Shows status of Successfully Installed" {
            $resultsAuto.Status | Should -Be "Successfully Installed"
        }

        It "Installs to specified path" {
            $resultsAuto.InstallPath | Should -Be $tempInstallPathAuto
        }
    }

    Context "Testing existing installation detection" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # First install SqlPackage
            $tempInstallPathExisting = Join-Path ([System.IO.Path]::GetTempPath()) "SqlPackageTestExisting_$(Get-Random)"
            $firstInstall = Install-DbaSqlPackage -Method Zip -InstallPath $tempInstallPathExisting -AddToPath -Force

            # Add to PATH temporarily for this test
            $isWindows = if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWindows } else { $env:OS -eq "Windows_NT" }
            $separator = if ($isWindows) { ";" } else { ":" }
            $env:PATH = "$env:PATH$separator$tempInstallPathExisting"

            # Try to install again without Force
            $secondInstall = Install-DbaSqlPackage -Method Zip -InstallPath $tempInstallPathExisting -Verbose:$false

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up test installation
            if (Test-Path $tempInstallPathExisting) {
                Remove-Item $tempInstallPathExisting -Recurse -Force
            }

            # Clean up PATH
            $isWindows = if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWindows } else { $env:OS -eq "Windows_NT" }
            $separator = if ($isWindows) { ";" } else { ":" }
            $env:PATH = $env:PATH -replace "$separator$tempInstallPathExisting", ""

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "First installation succeeds" {
            $firstInstall.Status | Should -Be "Successfully Installed"
        }

        It "Second installation detects existing installation" {
            $secondInstall.Status | Should -Be "Already Installed"
        }

        It "Second installation uses existing method" {
            $secondInstall.Method | Should -Be "Existing"
        }
    }
}