param($ModuleName = 'dbatools')

Describe "Add-DbaAgReplica" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Add-DbaAgReplica
        }
        $knownParameters = @(
            'SqlInstance',
            'SqlCredential',
            'Name',
            'ClusterType',
            'AvailabilityMode',
            'FailoverMode',
            'BackupPriority',
            'ConnectionModeInPrimaryRole',
            'ConnectionModeInSecondaryRole',
            'SeedingMode',
            'Endpoint',
            'EndpointUrl',
            'Passthru',
            'ReadOnlyRoutingList',
            'ReadonlyRoutingConnectionUrl',
            'Certificate',
            'ConfigureXESession',
            'SessionTimeout',
            'InputObject',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" -ForEach $knownParameters {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $agname = "dbatoolsci_agroup"
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
            $replicaName = $ag.PrimaryReplica
        }
        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
        }
        Context "gets ag replicas" {
            BeforeAll {
                $agname = "dbatoolsci_add_replicagroup"
                $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
                $replicaName = $ag.PrimaryReplica
            }

            It "returns results with proper data" {
                $results = Get-DbaAgReplica -SqlInstance $global:instance3
                $results.AvailabilityGroup | Should -Contain $agname
                $results.Role | Should -Contain 'Primary'
                $results.AvailabilityMode | Should -Contain 'SynchronousCommit'
                $results.FailoverMode | Should -Contain 'Manual'
            }
            It "returns just one result" {
                $results = Get-DbaAgReplica -SqlInstance $global:instance3 -Replica $replicaName -AvailabilityGroup $agname
                $results.AvailabilityGroup | Should -Be $agname
                $results.Role | Should -Be 'Primary'
                $results.AvailabilityMode | Should -Be 'SynchronousCommit'
                $results.FailoverMode | Should -Be 'Manual'
            }
        }
    }
}
#$global:instance2 for appveyor
