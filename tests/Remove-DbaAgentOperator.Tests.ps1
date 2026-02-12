#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentOperator",
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
                "Operator",
                "ExcludeOperator",
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
        $operatorsToCleanup = @()
        $instanceConnection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $operatorEmail1 = "test1$($random)@test.com"
        $operatorEmail2 = "test2$($random)@test.com"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created operators
        $splatCleanup = @{
            SqlInstance = $instanceConnection
        }
        $null = Remove-DbaAgentOperator @splatCleanup -Operator $operatorEmail1 -ErrorAction SilentlyContinue
        $null = Remove-DbaAgentOperator @splatCleanup -Operator $operatorEmail2 -ErrorAction SilentlyContinue

        foreach ($operatorName in $operatorsToCleanup) {
            $null = Remove-DbaAgentOperator @splatCleanup -Operator $operatorName -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Remove Agent Operator is removed properly" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputOperatorName = "dbatoolsci_outputtest_$(Get-Random)"
            $null = New-DbaAgentOperator -SqlInstance $instanceConnection -Operator $outputOperatorName
            $script:outputValidationResult = Remove-DbaAgentOperator -SqlInstance $instanceConnection -Operator $outputOperatorName -Confirm:$false

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $null = Remove-DbaAgentOperator -SqlInstance $instanceConnection -Operator $outputOperatorName -ErrorAction SilentlyContinue
        }

        It "Should have no operator with that name" {
            Remove-DbaAgentOperator -SqlInstance $instanceConnection -Operator $operatorEmail1
            $results = (Get-DbaAgentOperator -SqlInstance $instanceConnection -Operator $operatorEmail1).Count
            $results | Should -BeExactly 0
        }

        It "supports piping SQL Agent operator" {
            $operatorName = "dbatoolsci_test_$(Get-Random)"
            $operatorsToCleanup += $operatorName
            $null = New-DbaAgentOperator -SqlInstance $instanceConnection -Operator $operatorName
            (Get-DbaAgentOperator -SqlInstance $instanceConnection -Operator $operatorName) | Should -Not -BeNullOrEmpty
            Get-DbaAgentOperator -SqlInstance $instanceConnection -Operator $operatorName | Remove-DbaAgentOperator
            (Get-DbaAgentOperator -SqlInstance $instanceConnection -Operator $operatorName) | Should -BeNullOrEmpty
        }

        Context "Output validation" {
            It "Returns output of the documented type" {
                $script:outputValidationResult | Should -Not -BeNullOrEmpty
                $script:outputValidationResult | Should -BeOfType PSCustomObject
            }

            It "Has the expected properties" {
                $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Status", "IsRemoved")
                foreach ($prop in $expectedProperties) {
                    $script:outputValidationResult.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
                }
            }

            It "Has correct values for removal output" {
                $script:outputValidationResult.Status | Should -Be "Dropped"
                $script:outputValidationResult.IsRemoved | Should -BeTrue
                $script:outputValidationResult.Name | Should -Be $outputOperatorName
                $script:outputValidationResult.ComputerName | Should -Not -BeNullOrEmpty
                $script:outputValidationResult.InstanceName | Should -Not -BeNullOrEmpty
                $script:outputValidationResult.SqlInstance | Should -Not -BeNullOrEmpty
            }
        }
    }
}