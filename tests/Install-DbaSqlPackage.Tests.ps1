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

        It "Returns an object with the expected properties" {
            $result = $results
            $ExpectedProps = 'Name', 'Path', 'Installed'
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
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

    Context "Output validation" {
        BeforeAll {
            # SqlPackage should already be installed from the previous context
            $result = Install-DbaSqlPackage
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $result.PSObject.Properties.Name | Should -Contain "Name"
            $result.PSObject.Properties.Name | Should -Contain "Path"
            $result.PSObject.Properties.Name | Should -Contain "Installed"
        }

        It "Has correct values for standard properties" {
            $result.Installed | Should -BeTrue
            $result.Path | Should -Not -BeNullOrEmpty
            $result.Name | Should -Not -BeNullOrEmpty
        }
    }
}
