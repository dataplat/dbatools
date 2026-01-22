#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaPfRelog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Destination",
                "Type",
                "Append",
                "AllowClobber",
                "PerformanceCounter",
                "PerformanceCounterPath",
                "Interval",
                "BeginTime",
                "EndTime",
                "ConfigPath",
                "Summary",
                "InputObject",
                "Multithread",
                "AllTime",
                "Raw",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a test .blg file for testing output
            # Note: This requires an actual .blg file. In real scenarios, tests would need a fixture file.
            # For now, we'll skip if no test file is available
            $testBlgPath = "$env:TEMP\dbatools_test_perfmon.blg"
            $hasTestFile = Test-Path -Path $testBlgPath
        }

        It "Returns System.IO.FileInfo when converting a .blg file" -Skip:(-not $hasTestFile) {
            $result = Invoke-DbaPfRelog -Path $testBlgPath -AllowClobber -EnableException
            $result | Should -BeOfType [System.IO.FileInfo]
        }

        It "Has the RelogFile property added to output" -Skip:(-not $hasTestFile) {
            $result = Invoke-DbaPfRelog -Path $testBlgPath -AllowClobber -EnableException
            $result.PSObject.Properties.Name | Should -Contain 'RelogFile' -Because "RelogFile property should be added by the command"
            $result.RelogFile | Should -Be $true
        }

        It "Has standard FileInfo properties" -Skip:(-not $hasTestFile) {
            $result = Invoke-DbaPfRelog -Path $testBlgPath -AllowClobber -EnableException
            $expectedProps = @(
                'FullName',
                'Name',
                'Directory',
                'DirectoryName',
                'Extension',
                'Length',
                'Attributes',
                'CreationTime',
                'LastAccessTime',
                'LastWriteTime'
            )
            foreach ($prop in $expectedProps) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "FileInfo property '$prop' should be available"
            }
        }
    }

    Context "Output with -Raw" {
        BeforeAll {
            $testBlgPath = "$env:TEMP\dbatools_test_perfmon.blg"
            $hasTestFile = Test-Path -Path $testBlgPath
        }

        It "Returns String when -Raw is specified" -Skip:(-not $hasTestFile) {
            $result = Invoke-DbaPfRelog -Path $testBlgPath -AllowClobber -Raw -EnableException
            $result | Should -BeOfType [String]
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>