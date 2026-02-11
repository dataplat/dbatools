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
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            # Generate log entries by running a dbatools command with verbose logging
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master -Verbose 4>$null
            # Get all recent log entries - the internal logging system captures messages regardless of verbose preference
            $result = Get-DbatoolsLog
        }

        It "Returns results" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Returns default output as PSCustomObject with expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @(
                "CallStack",
                "ComputerName",
                "File",
                "FunctionName",
                "Level",
                "Line",
                "Message",
                "ModuleName",
                "Runspace",
                "Tags",
                "TargetObject",
                "Timestamp",
                "Type",
                "Username"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present on the output object"
            }
        }

        It "Returns raw LogEntry objects when using -Raw" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $rawResult = Get-DbatoolsLog -Raw
            $rawResult | Should -Not -BeNullOrEmpty
            $rawResult[0].PSObject.TypeNames | Should -Contain "Dataplat.Dbatools.Message.LogEntry"
        }
    }
}