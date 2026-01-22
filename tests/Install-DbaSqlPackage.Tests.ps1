#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaSqlPackage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Scope",
                "Type",
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing SqlPackage installer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $results = Install-DbaSqlPackage -Force

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # Clean up is not needed as SqlPackage installation is typically permanent
            # and safe to leave installed for other tests
        }

        It "Should have installed SqlPackage successfully" {
            $results.Installed | Should -Be $true
        }

        It "Should return a valid installation path" {
            $results.Path | Should -Not -BeNullOrEmpty
            Test-Path $results.Path | Should -Be $true
        }

        It "Should be able to find SqlPackage after installation" {
            $sqlPackagePath = Get-DbaSqlPackagePath
            $sqlPackagePath | Should -Not -BeNullOrEmpty
            Test-Path $sqlPackagePath | Should -Be $true
        }

        It "SqlPackage executable should be functional" {
            $sqlPackagePath = Get-DbaSqlPackagePath
            if ($PSVersionTable.Platform -eq "Unix") {
                $testProcess = Start-Process -FilePath $sqlPackagePath -ArgumentList '/?' -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP/sqlpackage_test.txt" -RedirectStandardError "$env:TEMP/sqlpackage_error.txt"
            } else {
                $testProcess = Start-Process -FilePath $sqlPackagePath -ArgumentList '/?' -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\sqlpackage_test.txt" -RedirectStandardError "$env:TEMP\sqlpackage_error.txt"
            }
            $testProcess.ExitCode | Should -Be 0
            if ($PSVersionTable.Platform -eq "Unix") {
                Remove-Item "$env:TEMP/sqlpackage_test.txt" -ErrorAction SilentlyContinue
                Remove-Item "$env:TEMP/sqlpackage_error.txt" -ErrorAction SilentlyContinue
            } else {
                Remove-Item "$env:TEMP\sqlpackage_test.txt" -ErrorAction SilentlyContinue
                Remove-Item "$env:TEMP\sqlpackage_error.txt" -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Install-DbaSqlPackage -Force -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "Name",
                "Path",
                "Installed"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has Name property with correct executable name" {
            if ($PSVersionTable.Platform -eq "Unix") {
                $result.Name | Should -Be "sqlpackage"
            } else {
                $result.Name | Should -Be "SqlPackage.exe"
            }
        }

        It "Has Path property that points to a valid file" {
            $result.Path | Should -Not -BeNullOrEmpty
            Test-Path $result.Path | Should -Be $true
        }

        It "Has Installed property set to true" {
            $result.Installed | Should -Be $true
        }
    }

    Context "Output when already installed" {
        BeforeAll {
            # First ensure it's installed
            $null = Install-DbaSqlPackage -Force -EnableException
            # Then run without -Force to get "already installed" message
            $result = Install-DbaSqlPackage -EnableException
        }

        It "Includes Notes property when skipping installation" {
            $result.PSObject.Properties.Name | Should -Contain "Notes"
        }

        It "Notes property indicates installation was skipped" {
            $result.Notes | Should -Match "already exists"
            $result.Notes | Should -Match "Skipped installation"
        }
    }
}
