#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaNetworkCertificate",
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
    Context "When removing the network certificate from a default instance" {
        BeforeAll {
            $results = Remove-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceSingle -Confirm:$false -WarningVariable warn 3> $null
        }

        It "Should run without warning" {
            # The instance uses an auto-generated fallback certificate (none explicitly configured),
            # so the Certificate registry value is already empty and this clears a no-op; a status
            # object is still returned.
            $warn | Should -BeNullOrEmpty
        }

        It "Should return a status object with the expected properties" {
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "ServiceAccount", "RemovedThumbprint")
            foreach ($prop in $expectedProps) {
                $results.PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }
}