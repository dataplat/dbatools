#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcAvailableDisk",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Validate output" {
        It "Should execute without errors" {
            $result = Get-DbaWsfcAvailableDisk -ComputerName $TestConfig.InstanceHadr -WarningVariable WarnVar -OutVariable "global:dbatoolsciOutput"

            $WarnVar | Should -BeNullOrEmpty
            # Available disks may be empty if all disks are already assigned to the cluster
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" -Skip:(-not $global:dbatoolsciOutput) {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.Management.Infrastructure.CimInstance]
        }

        It "Should have the added ClusterName property" -Skip:(-not $global:dbatoolsciOutput) {
            $global:dbatoolsciOutput[0].ClusterName | Should -Not -BeNullOrEmpty
        }

        It "Should have the added ClusterFqdn property" -Skip:(-not $global:dbatoolsciOutput) {
            $global:dbatoolsciOutput[0].ClusterFqdn | Should -Not -BeNullOrEmpty
        }

        It "Should have the added State property" -Skip:(-not $global:dbatoolsciOutput) {
            $global:dbatoolsciOutput[0].PSObject.Properties.Name | Should -Contain "State"
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "MSCluster_AvailableDisk"
        }
    }
}