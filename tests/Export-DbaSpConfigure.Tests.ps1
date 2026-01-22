#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "FilePath",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $tempPath = [System.IO.Path]::GetTempPath()
            $result = Export-DbaSpConfigure -SqlInstance $TestConfig.instance1 -Path $tempPath -EnableException
        }

        AfterAll {
            if ($result.FullName -and (Test-Path $result.FullName)) {
                Remove-Item -Path $result.FullName -Force
            }
        }

        It "Returns the documented output type System.IO.FileInfo" {
            $result | Should -BeOfType [System.IO.FileInfo]
        }

        It "Has the expected FileInfo properties" {
            $expectedProps = @(
                'Name',
                'FullName',
                'Directory',
                'Length',
                'CreationTime',
                'LastWriteTime',
                'Extension',
                'Attributes'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available on FileInfo object"
            }
        }

        It "Creates a SQL script file with .sql extension" {
            $result.Extension | Should -Be '.sql'
        }

        It "Creates a file with sp_configure in the filename" {
            $result.Name | Should -Match 'sp_configure'
        }
    }
}
#
#    Integration test should appear below and are custom to the command you are writing.
#    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
#    for more guidence.
#