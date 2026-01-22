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

    Context "Output Validation" {
        BeforeAll {
            # Note: This test requires a Windows Server Failover Cluster with available disks
            # Skip if cluster is not available or no available disks exist
            try {
                $result = Get-DbaWsfcAvailableDisk -ComputerName $env:COMPUTERNAME -EnableException -ErrorAction Stop
            } catch {
                $result = $null
            }
        }

        It "Returns the documented output type" -Skip:($null -eq $result) {
            $result[0].PSObject.TypeNames | Should -Contain 'Microsoft.Management.Infrastructure.CimInstance#root/MSCluster/MSCluster_AvailableDisk'
        }

        It "Has the State property added by dbatools" -Skip:($null -eq $result) {
            $result[0].PSObject.Properties.Name | Should -Contain 'State' -Because "dbatools adds this property via Add-Member"
        }

        It "Has the ClusterName property added by dbatools" -Skip:($null -eq $result) {
            $result[0].PSObject.Properties.Name | Should -Contain 'ClusterName' -Because "dbatools adds this property via Add-Member"
        }

        It "Has the ClusterFqdn property added by dbatools" -Skip:($null -eq $result) {
            $result[0].PSObject.Properties.Name | Should -Contain 'ClusterFqdn' -Because "dbatools adds this property via Add-Member"
        }

        It "Has standard WMI properties from MSCluster_AvailableDisk" -Skip:($null -eq $result) {
            $expectedWmiProps = @(
                'Name',
                'Id',
                'Size',
                'Number'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedWmiProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' is a standard MSCluster_AvailableDisk WMI property"
            }
        }
    }
}