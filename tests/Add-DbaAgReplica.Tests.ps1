$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandUnderTest = Get-Command $CommandName
    }

    Context "Validate parameters" {
        It "Should have the correct parameters" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ClusterType -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter AvailabilityMode -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter FailoverMode -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter BackupPriority -Type Int32 -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ConnectionModeInPrimaryRole -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ConnectionModeInSecondaryRole -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter SeedingMode -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Endpoint -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter EndpointUrl -Type String[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Passthru -Type SwitchParameter -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ReadOnlyRoutingList -Type String[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ReadonlyRoutingConnectionUrl -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Certificate -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ConfigureXESession -Type SwitchParameter -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter SessionTimeout -Type Int32 -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InputObject -Type AvailabilityGroup -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_agroup"
        $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
        $replicaName = $ag.PrimaryReplica
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "gets ag replicas" {
        BeforeAll {
            # the only way to test, really, is to call New-DbaAvailabilityGroup which calls Add-DbaAgReplica
            $agname = "dbatoolsci_add_replicagroup"
            $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
            $replicaName = $ag.PrimaryReplica
        }

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
} #$script:instance2 for appveyor
