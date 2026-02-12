#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaExtendedProperty",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
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

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Get-DbaProcess -SqlInstance $InstanceSingle | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
        $newDbName = "dbatoolsci_newdb_$random"
        $db = New-DbaDatabase -SqlInstance $InstanceSingle -Name $newDbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $db | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {
        It "works" {
            $ep = $db | Add-DbaExtendedProperty -Name "Test_Database_Name" -Value $newDbName
            $results = $ep | Remove-DbaExtendedProperty
            $results.Name | Should -Be "Test_Database_Name"
            $results.Status | Should -Be "Dropped"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputPropName = "dbatoolsci_outputprop_$(Get-Random)"
            $outputEp = $db | Add-DbaExtendedProperty -Name $outputPropName -Value "test_value"
            $result = $outputEp | Remove-DbaExtendedProperty -Confirm:$false
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $result | Should -Not -BeNullOrEmpty
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "ParentName", "PropertyType", "Name", "Status")
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the correct values for a successful removal" {
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Dropped"
            $result.Name | Should -Be $outputPropName
        }
    }
}