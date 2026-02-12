#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaServerRole",
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
                "ServerRole",
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

        # Set variables. They are available in all the It blocks.
        $testInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $testRoleExecutor = "serverExecuter"
        $null = New-DbaServerRole -SqlInstance $testInstance -ServerRole $testRoleExecutor

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaServerRole -SqlInstance $testInstance -ServerRole $testRoleExecutor

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputRoleName = "dbatoolsci_outputrole_$(Get-Random)"
            $null = New-DbaServerRole -SqlInstance $testInstance -ServerRole $outputRoleName
            $script:outputForValidation = Remove-DbaServerRole -SqlInstance $testInstance -ServerRole $outputRoleName -Confirm:$false

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "It returns info about server-role removed" {
            $results = Remove-DbaServerRole -SqlInstance $testInstance -ServerRole $testRoleExecutor
            $results.ServerRole | Should -Be $testRoleExecutor
        }

        It "Should not return server-role" {
            $results = Get-DbaServerRole -SqlInstance $testInstance -ServerRole $testRoleExecutor
            $results | Should -Be $null
        }

        Context "Output validation" {
            It "Returns output of the documented type" {
                $script:outputForValidation | Should -Not -BeNullOrEmpty
                $script:outputForValidation | Should -BeOfType [PSCustomObject]
            }

            It "Has the expected properties" {
                $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "ServerRole", "Status")
                foreach ($prop in $expectedProperties) {
                    $script:outputForValidation.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
                }
            }

            It "Has the correct values for a successful removal" {
                $script:outputForValidation.Status | Should -Be "Success"
                $script:outputForValidation.ServerRole | Should -Be $outputRoleName
                $script:outputForValidation.ComputerName | Should -Not -BeNullOrEmpty
                $script:outputForValidation.InstanceName | Should -Not -BeNullOrEmpty
                $script:outputForValidation.SqlInstance | Should -Not -BeNullOrEmpty
            }
        }
    }

}
