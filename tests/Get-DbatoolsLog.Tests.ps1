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
    Context "Command actually works" {
        BeforeAll {
            # Generate some log entries by running a simple dbatools command
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "master"
            $results = Get-DbatoolsLog -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return log entries" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
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
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}