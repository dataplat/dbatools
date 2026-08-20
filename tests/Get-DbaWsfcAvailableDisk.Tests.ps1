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
    # These tests need a Windows failover cluster that can see a shared disk which is not part of the
    # cluster. No CI environment has one, so $TestConfig.ClusterStorage is empty there and these tests
    # skip. A lab that has a cluster sets it, and then a regression has to fail these tests.
    Context "Retrieving the available disks" -Skip:(-not $TestConfig.ClusterStorage) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $availableDisks = @(Get-DbaWsfcAvailableDisk -ComputerName $TestConfig.ClusterStorage)
            $wsfcCluster = Get-DbaWsfcCluster -ComputerName $TestConfig.ClusterStorage

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns at least one available disk" {
            $availableDisks | Should -Not -BeNullOrEmpty
        }

        It "Adds the cluster name and fqdn to every disk" {
            # The -PassThru that emits these objects used to sit on a NoteProperty that has been
            # removed, so this also guards against the command returning nothing at all.
            ($availableDisks | Where-Object ClusterName -ne $wsfcCluster.Name).Name | Should -BeNullOrEmpty
            ($availableDisks | Where-Object ClusterFqdn -ne $wsfcCluster.Fqdn).Name | Should -BeNullOrEmpty
        }

        It "Does not add an empty State property" {
            # MSCluster_AvailableDisk has no State property, so the command built its State
            # NoteProperty from an undefined variable and it was always empty.
            $availableDisks[0].PSObject.Properties.Name | Should -Not -Contain "State"
        }
    }
}