#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcSharedVolume",
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

    Context "Output Validation" -Tag IntegrationTests {
        BeforeAll {
            # This command requires WSFC which may not be available in all test environments
            # Skip if not running on a cluster or if Get-DbaWsfcCluster fails
            try {
                $result = Get-DbaWsfcSharedVolume -ComputerName $env:COMPUTERNAME -EnableException -ErrorAction Stop
            } catch {
                $result = $null
            }
        }

        It "Returns the documented output type" -Skip:($null -eq $result) {
            $result | Should -BeOfType [System.Management.ManagementObject]
        }

        It "Has the expected added properties" -Skip:($null -eq $result) {
            $expectedProps = @(
                'ClusterName',
                'ClusterFqdn',
                'State'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be added by dbatools"
            }
        }
    }
}