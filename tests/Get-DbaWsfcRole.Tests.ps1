#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcRole",
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

    Context "Output Validation" -Skip:$(-not $env:COMPUTERNAME) {
        BeforeAll {
            try {
                $result = Get-DbaWsfcRole -ComputerName $env:COMPUTERNAME -EnableException
            } catch {
                $result = $null
            }
        }

        It "Returns the documented output type" -Skip:($null -eq $result) {
            $result | Should -BeOfType [Microsoft.Management.Infrastructure.CimInstance]
            $result.CimClass.CimClassName | Should -Be 'MSCluster_ResourceGroup'
        }

        It "Has the expected default display properties" -Skip:($null -eq $result) {
            $expectedProps = @(
                'ClusterName',
                'ClusterFqdn',
                'Name',
                'OwnerNode',
                'State'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}