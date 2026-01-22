#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaExtendedProperty",
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
                "Database",
                "Name",
                "Value",
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

        # Create unique database name for this test run
        $random = Get-Random
        $newDbName = "dbatoolsci_newdb_$random"

        # Connect to instance and clean up any existing connections
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Get-DbaProcess -SqlInstance $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue

        # Create test database
        $db = New-DbaDatabase -SqlInstance $server2 -Name $newDbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup the test database
        $null = $db | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding extended properties" {
        It "Adds an extended property to the database" {
            $splatExtendedProperty = @{
                Name  = "Test_Database_Name"
                Value = "Sup"
            }
            $ep = $db | Add-DbaExtendedProperty @splatExtendedProperty
            $ep.Name | Should -Be "Test_Database_Name"
            $ep.ParentName | Should -Be $db.Name
            $ep.Value | Should -Be "Sup"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $splatExtendedProperty = @{
                Name            = "Test_Output_Validation"
                Value           = "TestValue"
                EnableException = $true
            }
            $result = $db | Add-DbaExtendedProperty @splatExtendedProperty
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ExtendedProperty]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ParentName',
                'Type',
                'Name',
                'Value'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}