#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Add-DbaAgReplica" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaAgReplica
            $expectedParameters = $TestConfig.CommonParameters

            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Name",
                "ClusterType",
                "AvailabilityMode",
                "FailoverMode",
                "BackupPriority",
                "ConnectionModeInPrimaryRole",
                "ConnectionModeInSecondaryRole",
                "SeedingMode",
                "Endpoint",
                "EndpointUrl",
                "Passthru",
                "ReadOnlyRoutingList",
                "ReadonlyRoutingConnectionUrl",
                "Certificate",
                "ConfigureXESession",
                "SessionTimeout",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have exactly the expected parameters" {
            $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $actualParameters | Should -BeNullOrEmpty
        }

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }
    }
}

Describe "Add-DbaAgReplica" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_agroup"
        $splat = @{
            Primary       = $TestConfig.instance3
            Name          = $agname
            ClusterType   = "None"
            FailoverMode  = "Manual"
            Certificate   = "dbatoolsci_AGCert"
            Confirm       = $false
        }
        $ag = New-DbaAvailabilityGroup @splat
        $replicaName = $ag.PrimaryReplica
    }

    AfterAll {
        Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $agname = "dbatoolsci_add_replicagroup"
            $splat = @{
                Primary       = $TestConfig.instance3
                Name          = $agname
                ClusterType   = "None"
                FailoverMode  = "Manual"
                Certificate   = "dbatoolsci_AGCert"
                Confirm       = $false
            }
            $ag = New-DbaAvailabilityGroup @splat
            $replicaName = $ag.PrimaryReplica
        }

        It "Returns results with proper data" {
            $results = Get-DbaAgReplica -SqlInstance $TestConfig.instance3
            $results.AvailabilityGroup | Should -Contain $agname
            $results.Role | Should -Contain 'Primary'
            $results.AvailabilityMode | Should -Contain 'SynchronousCommit'
            $results.FailoverMode | Should -Contain 'Manual'
        }

        It "Returns just one result" {
            $results = Get-DbaAgReplica -SqlInstance $TestConfig.instance3 -Replica $replicaName -AvailabilityGroup $agname
            $results.AvailabilityGroup | Should -Be $agname
            $results.Role | Should -Be 'Primary'
            $results.AvailabilityMode | Should -Be 'SynchronousCommit'
            $results.FailoverMode | Should -Be 'Manual'
        }
    }
}
