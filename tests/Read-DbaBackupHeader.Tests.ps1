#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaBackupHeader",
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
                "Simple",
                "FileList",
                "StorageCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When Path is a folder" {
        It "Warns that it needs a file and returns nothing" {
            # The message used to be built from a broken string literal, "Path ("$p") should be a file, not a folder",
            # which handed $p to Stop-Function as a positional argument and turned the warning into a binding error.
            $splatFolder = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Path          = $TestConfig.Temp
                WarningAction = "SilentlyContinue"
            }
            $results = Read-DbaBackupHeader @splatFolder
            $results | Should -BeNullOrEmpty
            ($WarnVar -join " ") | Should -BeLike "*should be a file, not a folder*"
        }
    }
}
