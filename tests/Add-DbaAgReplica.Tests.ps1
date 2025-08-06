#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName               = "dbatools",
    $CommandName              = [System.IO.Path]::GetFileName($PSCommandPath.Replace('.Tests.ps1', '')),
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaAgReplica
            $expected = $TestConfig.CommonParameters
            $expected += @(
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
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag "IntegrationTests" {
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
