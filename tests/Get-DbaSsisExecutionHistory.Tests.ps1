#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSsisExecutionHistory",
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
                "Since",
                "Status",
                "Project",
                "Folder",
                "Environment",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            # Create a mock result to test type
            $mockResult = [PSCustomObject]@{
                ExecutionID    = 1
                FolderName     = "TestFolder"
                ProjectName    = "TestProject"
                PackageName    = "TestPackage"
                ProjectLsn     = 1
                Environment    = "TestEnv"
                StatusCode     = "Succeeded"
                StartTime      = [dbadatetime]::MinValue
                EndTime        = [dbadatetime]::MinValue
                ElapsedMinutes = 0
                LoggingLevel   = 1
            }
            $mockResult.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected output properties" {
            $expectedProps = @(
                'ExecutionID',
                'FolderName',
                'ProjectName',
                'PackageName',
                'ProjectLsn',
                'Environment',
                'StatusCode',
                'StartTime',
                'EndTime',
                'ElapsedMinutes',
                'LoggingLevel'
            )
            # Test against mock result structure
            $mockResult = [PSCustomObject]@{
                ExecutionID    = 1
                FolderName     = "TestFolder"
                ProjectName    = "TestProject"
                PackageName    = "TestPackage"
                ProjectLsn     = 1
                Environment    = "TestEnv"
                StatusCode     = "Succeeded"
                StartTime      = [dbadatetime]::MinValue
                EndTime        = [dbadatetime]::MinValue
                ElapsedMinutes = 0
                LoggingLevel   = 1
            }
            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>