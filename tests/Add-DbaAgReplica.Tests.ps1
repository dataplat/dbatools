param($ModuleName = 'dbatools')

Describe "Add-DbaAgReplica Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Import the function
        . (Join-Path -Path $PSScriptRoot -ChildPath '..\functions\Add-DbaAgReplica.ps1')
    }

    Context "Validate parameters" {
        BeforeDiscovery {
            $commandInfo = Get-Command Add-DbaAgReplica
            $parameterInfo = $commandInfo.Parameters
        }

        It "Should have parameter <_>" -ForEach @(
            'SqlInstance', 'SqlCredential', 'Name', 'ClusterType', 'AvailabilityMode', 'FailoverMode', 'BackupPriority',
            'ConnectionModeInPrimaryRole', 'ConnectionModeInSecondaryRole', 'SeedingMode', 'Endpoint', 'EndpointUrl',
            'Passthru', 'ReadOnlyRoutingList', 'ReadonlyRoutingConnectionUrl', 'Certificate', 'ConfigureXESession',
            'SessionTimeout', 'InputObject', 'EnableException'
        ) {
            $parameterInfo.ContainsKey($_) | Should -Be $true
        }

        It "SqlInstance parameter should be mandatory" {
            $parameterInfo['SqlInstance'].Attributes.Mandatory | Should -Be $true
        }

        It "AvailabilityMode parameter should accept 'AsynchronousCommit' and 'SynchronousCommit'" {
            $parameterInfo['AvailabilityMode'].Attributes.ValidValues | Should -Be @('AsynchronousCommit', 'SynchronousCommit')
        }

        It "FailoverMode parameter should accept 'Automatic', 'Manual', and 'External'" {
            $parameterInfo['FailoverMode'].Attributes.ValidValues | Should -Be @('Automatic', 'Manual', 'External')
        }
    }
}

Describe "Add-DbaAgReplica Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_agroup"
        $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
        $replicaName = $ag.PrimaryReplica
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "adds ag replicas" {
        $agname = "dbatoolsci_add_replicagroup"
        $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
        $replicaName = $ag.PrimaryReplica

        It "returns results with proper data" {
            $results = Get-DbaAgReplica -SqlInstance $script:instance3
            $results.AvailabilityGroup | Should -Contain $agname
            $results.Role | Should -Contain 'Primary'
            $results.AvailabilityMode | Should -Contain 'SynchronousCommit'
            $results.FailoverMode | Should -Contain 'Manual'
        }

        It "returns just one result" {
            $results = Get-DbaAgReplica -SqlInstance $script:instance3 -Replica $replicaName -AvailabilityGroup $agname
            $results.AvailabilityGroup | Should -Be $agname
            $results.Role | Should -Be 'Primary'
            $results.AvailabilityMode | Should -Be 'SynchronousCommit'
            $results.FailoverMode | Should -Be 'Manual'
        }
    }
}

#$script:instance2 for appveyor
