#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcResource",
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
            $result = Get-DbaWsfcResource -ComputerName $env:COMPUTERNAME -EnableException
        }

        It "Returns MSCluster_Resource objects" {
            if ($result) {
                $result[0].PSObject.TypeNames | Should -Contain 'System.Management.ManagementObject#root\MSCluster\MSCluster_Resource'
            } else {
                Set-ItResult -Skipped -Because "No cluster resources found on this computer"
            }
        }

        It "Has the expected default display properties" {
            if ($result) {
                $expectedProps = @(
                    'ClusterName',
                    'ClusterFqdn',
                    'Name',
                    'State',
                    'Type',
                    'OwnerGroup',
                    'OwnerNode',
                    'PendingTimeout',
                    'PersistentState',
                    'QuorumCapable',
                    'RequiredDependencyClasses',
                    'RequiredDependencyTypes',
                    'RestartAction',
                    'RestartDelay',
                    'RestartPeriod',
                    'RestartThreshold',
                    'RetryPeriodOnFailure',
                    'SeparateMonitor'
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
                }
            } else {
                Set-ItResult -Skipped -Because "No cluster resources found on this computer"
            }
        }

        It "Has dbatools-added properties" {
            if ($result) {
                $result[0].PSObject.Properties.Name | Should -Contain 'State' -Because "State is added via Add-Member"
                $result[0].PSObject.Properties.Name | Should -Contain 'ClusterName' -Because "ClusterName is added via Add-Member"
                $result[0].PSObject.Properties.Name | Should -Contain 'ClusterFqdn' -Because "ClusterFqdn is added via Add-Member"
            } else {
                Set-ItResult -Skipped -Because "No cluster resources found on this computer"
            }
        }
    }
}