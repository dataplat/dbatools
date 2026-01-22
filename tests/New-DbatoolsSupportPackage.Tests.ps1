#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbatoolsSupportPackage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Variables",
                "PassThru",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $testPath = Join-Path $env:TEMP "DbatoolsTestPackage"
            if (-not (Test-Path $testPath)) {
                $null = New-Item -Path $testPath -ItemType Directory -Force
            }
            $result = New-DbatoolsSupportPackage -Path $testPath -EnableException
        }

        AfterAll {
            if ($result -and (Test-Path $result.FullName)) {
                Remove-Item -Path $result.FullName -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $testPath) {
                Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [System.IO.FileInfo]
        }

        It "Has the expected FileInfo properties" {
            $expectedProps = @(
                'FullName',
                'Name',
                'DirectoryName',
                'Directory',
                'Length',
                'Exists',
                'CreationTime',
                'LastWriteTime',
                'LastAccessTime'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }

        It "Creates a ZIP file" {
            $result.Name | Should -Match "^dbatools_support_pack_\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2}\.zip$"
            $result.Exists | Should -Be $true
            $result.Extension | Should -Be ".zip"
        }

        It "Creates a file with content" {
            $result.Length | Should -BeGreaterThan 0
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>