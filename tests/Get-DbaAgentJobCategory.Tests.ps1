#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentJobCategory",
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
                "Category",
                "CategoryType",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command gets job categories" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category dbatoolsci_testcategory, dbatoolsci_testcategory2

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category dbatoolsci_testcategory, dbatoolsci_testcategory2

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should get at least 2 categories" {
            $results = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -match "dbatoolsci"
            $results.Count | Should -BeGreaterThan 1
        }

        It "Should get the dbatoolsci_testcategory category" {
            $results = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category dbatoolsci_testcategory | Where-Object Name -match "dbatoolsci"
            $results.Count | Should -BeExactly 1
        }

        It "Should get at least 1 LocalJob" {
            $results = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -CategoryType LocalJob | Where-Object Name -match "dbatoolsci"
            $results.Count | Should -BeGreaterThan 1
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns the documented output type" {
            $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobCategory]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'ID',
                'CategoryType',
                'JobCount'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}