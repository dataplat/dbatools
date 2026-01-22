#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FunctionName",
                "ModuleName",
                "Target",
                "Tag",
                "Last",
                "Skip",
                "Runspace",
                "Level",
                "Raw",
                "Errors",
                "LastError"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Generate a log entry by running a simple command
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -EnableException -WarningAction SilentlyContinue
            $result = Get-DbatoolsLog -Last 1
        }

        It "Returns PSCustomObject by default" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'CallStack',
                'ComputerName',
                'File',
                'FunctionName',
                'Level',
                'Line',
                'Message',
                'ModuleName',
                'Runspace',
                'Tags',
                'TargetObject',
                'Timestamp',
                'Type',
                'Username'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output with -Raw" {
        BeforeAll {
            # Generate a log entry by running a simple command
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -EnableException -WarningAction SilentlyContinue
            $result = Get-DbatoolsLog -Last 1 -Raw
        }

        It "Returns Dataplat.Dbatools.Message.LogEntry when -Raw specified" {
            $result[0] | Should -BeOfType [Dataplat.Dbatools.Message.LogEntry]
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>