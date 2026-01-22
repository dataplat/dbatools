#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaExtendedProperty",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "Value",
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
        $db | Add-DbaExtendedProperty -Name "Test_Database_Name" -Value $newDbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $db | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Commands work as expected" {
        It "Works" {
            $ep = Get-DbaExtendedProperty -SqlInstance $InstanceSingle -Name "Test_Database_Name"
            $newep = $ep | Set-DbaExtendedProperty -Value "Test_Database_Value"
            $newep.Name | Should -Be "Test_Database_Name"
            $newep.Value | Should -Be "Test_Database_Value"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $ep = Get-DbaExtendedProperty -SqlInstance $InstanceSingle -Name "Test_Database_Name" -EnableException
            $result = $ep | Set-DbaExtendedProperty -Value "OutputValidation_$random" -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ExtendedProperty]
        }

        It "Has the expected properties documented in .OUTPUTS" {
            $expectedProps = @(
                'Name',
                'Value',
                'ID',
                'Parent',
                'State',
                'Urn',
                'Properties'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available on ExtendedProperty object"
            }
        }

        It "Returns the updated value" {
            $result.Value | Should -Be "OutputValidation_$random"
        }
    }
}