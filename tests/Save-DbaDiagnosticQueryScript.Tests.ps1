#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Save-DbaDiagnosticQueryScript",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $tempPath = [System.IO.Path]::GetTempPath()
            $testPath = Join-Path -Path $tempPath -ChildPath "dbatools_test_$(Get-Random)"
            $null = New-Item -Path $testPath -ItemType Directory -Force
        }

        AfterAll {
            if (Test-Path $testPath) {
                Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Returns System.IO.FileInfo objects" {
            $result = Save-DbaDiagnosticQueryScript -Path $testPath -EnableException
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [System.IO.FileInfo]
        }

        It "Has the expected FileInfo properties" {
            $result = Save-DbaDiagnosticQueryScript -Path $testPath -EnableException
            $expectedProps = @(
                'FullName',
                'Name',
                'Extension',
                'Length',
                'CreationTime',
                'LastWriteTime',
                'Directory',
                'Attributes'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in FileInfo output"
            }
        }

        It "Downloads files with .sql extension" {
            $result = Save-DbaDiagnosticQueryScript -Path $testPath -EnableException
            $result.Extension | Should -Be ".sql"
        }

        It "Downloads files to the specified path" {
            $result = Save-DbaDiagnosticQueryScript -Path $testPath -EnableException
            $result.Directory.FullName | Should -Be $testPath
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>