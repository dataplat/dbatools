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
}

Describe $CommandName -Tag IntegrationTests {
    # These tests need a Windows failover cluster. No CI environment has one, so
    # $TestConfig.ClusterStorage is empty there and these tests skip. A lab that has a cluster sets
    # it, and then a regression has to fail these tests.
    Context "Retrieving the roles" -Skip:(-not $TestConfig.ClusterStorage) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $wsfcRoles = @(Get-DbaWsfcRole -ComputerName $TestConfig.ClusterStorage)
            # The same WMI class, read by the command that always translated its state correctly.
            $wsfcResourceGroups = @(Get-DbaWsfcResourceGroup -ComputerName $TestConfig.ClusterStorage)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns at least one role" {
            $wsfcRoles | Should -Not -BeNullOrEmpty
        }

        It "Translates the state of every role" {
            # The state was read from $resource.State, a variable this command never assigns, so it
            # was empty for every role on every cluster.
            $untranslatedRoles = ($wsfcRoles | Where-Object { $PSItem.State -notin "Unknown", "Online", "Offline", "Failed" }).Name
            $untranslatedRoles | Should -BeNullOrEmpty
        }

        It "Reports the same state per role as Get-DbaWsfcResourceGroup" {
            # Both commands read MSCluster_ResourceGroup. This command used to add one single state
            # to the whole collection instead of looping, so a cluster whose roles are not all in the
            # same state told them apart.
            foreach ($wsfcRole in $wsfcRoles) {
                $resourceGroup = $wsfcResourceGroups | Where-Object Name -eq $wsfcRole.Name
                $wsfcRole.State | Should -Be $resourceGroup.State -Because "role $($wsfcRole.Name) must report the state of its resource group"
            }
        }

        It "Adds the cluster name and fqdn to every role" {
            ($wsfcRoles | Where-Object ClusterName -ne $TestConfig.ClusterStorage).Name | Should -BeNullOrEmpty
            ($wsfcRoles | Where-Object { $PSItem.ClusterFqdn -notlike "$($TestConfig.ClusterStorage).*" }).Name | Should -BeNullOrEmpty
        }
    }
}