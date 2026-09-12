#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaForceNetworkEncryption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
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

        # Remember the state of the instance, so that AfterAll can put it back.
        $forceEncryptionBefore = (Get-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle).ForceEncryption

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($forceEncryptionBefore) {
            $null = Enable-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When disabling force network encryption" {
        It "Returns results with ForceEncryption set to false" {
            $results = Disable-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -EnableException
            $results.ForceEncryption | Should -BeFalse
        }
    }
}