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
    Context "When disabling force network encryption" {
        It "Returns results with ForceEncryption set to false" {
            $results = Disable-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -EnableException
            $results.ForceEncryption | Should -BeFalse
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputResult = Disable-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns output of type PSCustomObject" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ForceEncryption",
                "CertificateThumbprint"
            )
            foreach ($prop in $expectedProps) {
                $outputResult[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}