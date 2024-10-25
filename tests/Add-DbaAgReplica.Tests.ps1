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

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $command.Parameters.Keys | Should -BeNullOrEmpty
        }
    }
}

Describe "Add-DbaAgReplica" -Tag "IntegrationTests" {
    BeforeAll {
        $primaryAgName = "dbatoolsci_agroup"
        $splatPrimary = @{
            Primary      = $TestConfig.instance3
            Name         = $primaryAgName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
            Confirm      = $false
        }
        $primaryAg = New-DbaAvailabilityGroup @splatPrimary
        $replicaName = $primaryAg.PrimaryReplica
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $primaryAgName -Confirm:$false
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $replicaAgName = "dbatoolsci_add_replicagroup"
            $splatRepAg = @{
                Primary      = $TestConfig.instance3
                Name         = $replicaAgName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Certificate  = "dbatoolsci_AGCert"
                Confirm      = $false
            }
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg
        }

        It "Returns results with proper data" {
            $results = Get-DbaAgReplica -SqlInstance $TestConfig.instance3
            $results.AvailabilityGroup | Should -Contain $replicaAgName
            $results.Role | Should -Contain 'Primary'
            $results.AvailabilityMode | Should -Contain 'SynchronousCommit'
            $results.FailoverMode | Should -Contain 'Manual'
        }

        It "Returns just one result for a specific replica" {
            $results = Get-DbaAgReplica -SqlInstance $TestConfig.instance3 -Replica $replicaName -AvailabilityGroup $replicaAgName
            $results.AvailabilityGroup | Should -Be $replicaAgName
            $results.Role | Should -Be 'Primary'
            $results.AvailabilityMode | Should -Be 'SynchronousCommit'
            $results.FailoverMode | Should -Be 'Manual'
        }
    }
} #$TestConfig.instance2 for appveyor
