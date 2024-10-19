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
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have ClusterType parameter" {
            $CommandUnderTest | Should -HaveParameter ClusterType
        }
        It "Should have AvailabilityMode parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityMode
        }
        It "Should have FailoverMode parameter" {
            $CommandUnderTest | Should -HaveParameter FailoverMode
        }
        It "Should have BackupPriority parameter" {
            $CommandUnderTest | Should -HaveParameter BackupPriority
        }
        It "Should have ConnectionModeInPrimaryRole parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInPrimaryRole
        }
        It "Should have ConnectionModeInSecondaryRole parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInSecondaryRole
        }
        It "Should have SeedingMode parameter" {
            $CommandUnderTest | Should -HaveParameter SeedingMode
        }
        It "Should have Endpoint parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint
        }
        It "Should have EndpointUrl parameter" {
            $CommandUnderTest | Should -HaveParameter EndpointUrl
        }
        It "Should have Passthru parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru
        }
        It "Should have ReadOnlyRoutingList parameter" {
            $CommandUnderTest | Should -HaveParameter ReadOnlyRoutingList
        }
        It "Should have ReadonlyRoutingConnectionUrl parameter" {
            $CommandUnderTest | Should -HaveParameter ReadonlyRoutingConnectionUrl
        }
        It "Should have Certificate parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate
        }
        It "Should have ConfigureXESession parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigureXESession
        }
        It "Should have SessionTimeout parameter" {
            $CommandUnderTest | Should -HaveParameter SessionTimeout
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
