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
            $results.Successful | Should -Be $true
        }

        It "Returns an object with the expected properties" {
            $result = $results
            $ExpectedProps = 'ComputerName', 'Successful', 'Version', 'Path'
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should return a valid installation path" {
            $results.Path | Should -Not -BeNullOrEmpty
            Test-Path $results.Path | Should -Be $true
        }

        It "Should have a valid version" {
            $results.Version | Should -Not -BeNullOrEmpty
        }

        It "Should return the correct computer name" {
            $results.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It "XESmartTarget executable should exist" {
            $xeSmartTargetExe = Join-Path $results.Path "XESmartTarget.exe"
            Test-Path $xeSmartTargetExe | Should -Be $true
        }

        It "Should install required DLL files" {
            $dllFiles = @("XESmartTarget.Core.dll")
            foreach ($dll in $dllFiles) {
                $dllPath = Join-Path $results.Path $dll
                Test-Path $dllPath | Should -Be $true
            }
        }

        It "Should be accessible via Get-XESmartTargetPath" {
            $xeSmartTargetPath = Get-XESmartTargetPath
            $xeSmartTargetPath | Should -Not -BeNullOrEmpty
            Test-Path $xeSmartTargetPath | Should -Be $true
        }
    }
}