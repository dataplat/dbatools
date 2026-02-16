#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccMemoryStatus",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $expectedProps = @(
            "ComputerName",
            "InstanceName",
            "RecordSet",
            "RowId",
            "RecordSetId",
            "Type",
            "Name",
            "Value",
            "ValueType"
        )

        $memoryStatusResults = Get-DbaDbccMemoryStatus -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # No cleanup needed for this read-only command

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output" {
        It "Should return all expected properties" {
            foreach ($prop in $expectedProps) {
                $p = $memoryStatusResults[0].PSObject.Properties[$prop]
                $p.Name | Should -Be $prop
            }
        }
    }

    Context "Command returns proper info" {
        It "returns results for DBCC MEMORYSTATUS" {
            $memoryStatusResults.Count | Should -BeGreaterThan 0
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
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "RecordSet",
                "RowId",
                "RecordSetId",
                "Type",
                "Name",
                "Value",
                "ValueType"
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