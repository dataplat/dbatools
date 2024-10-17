param($ModuleName = 'dbatools')

Describe "Add-DbaAgReplica" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaAgReplica
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String
        }
        It "Should have ClusterType parameter" {
            $CommandUnderTest | Should -HaveParameter ClusterType -Type String
        }
        It "Should have AvailabilityMode parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityMode -Type String
        }
        It "Should have FailoverMode parameter" {
            $CommandUnderTest | Should -HaveParameter FailoverMode -Type String
        }
        It "Should have BackupPriority parameter" {
            $CommandUnderTest | Should -HaveParameter BackupPriority -Type Int32
        }
        It "Should have ConnectionModeInPrimaryRole parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInPrimaryRole -Type String
        }
        It "Should have ConnectionModeInSecondaryRole parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInSecondaryRole -Type String
        }
        It "Should have SeedingMode parameter" {
            $CommandUnderTest | Should -HaveParameter SeedingMode -Type String
        }
        It "Should have Endpoint parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint -Type String
        }
        It "Should have EndpointUrl parameter" {
            $CommandUnderTest | Should -HaveParameter EndpointUrl -Type String[]
        }
        It "Should have Passthru parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru -Type Switch
        }
        It "Should have ReadOnlyRoutingList parameter" {
            $CommandUnderTest | Should -HaveParameter ReadOnlyRoutingList -Type String[]
        }
        It "Should have ReadonlyRoutingConnectionUrl parameter" {
            $CommandUnderTest | Should -HaveParameter ReadonlyRoutingConnectionUrl -Type String
        }
        It "Should have Certificate parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate -Type String
        }
        It "Should have ConfigureXESession parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigureXESession -Type Switch
        }
        It "Should have SessionTimeout parameter" {
            $CommandUnderTest | Should -HaveParameter SessionTimeout -Type Int32
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type AvailabilityGroup
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            $agname = "dbatoolsci_agroup"
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
            $replicaName = $ag.PrimaryReplica
        }
        AfterAll {
            Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
        }
        It "gets ag replicas" {
            $agname = "dbatoolsci_add_replicagroup"
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
            $replicaName = $ag.PrimaryReplica

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

#$global:instance2 for appveyor
