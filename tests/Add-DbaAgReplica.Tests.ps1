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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String
        }
        It "Should have ClusterType parameter" {
            $CommandUnderTest | Should -HaveParameter ClusterType -Type System.String
        }
        It "Should have AvailabilityMode parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityMode -Type System.String
        }
        It "Should have FailoverMode parameter" {
            $CommandUnderTest | Should -HaveParameter FailoverMode -Type System.String
        }
        It "Should have BackupPriority parameter" {
            $CommandUnderTest | Should -HaveParameter BackupPriority -Type System.Int32
        }
        It "Should have ConnectionModeInPrimaryRole parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInPrimaryRole -Type System.String
        }
        It "Should have ConnectionModeInSecondaryRole parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInSecondaryRole -Type System.String
        }
        It "Should have SeedingMode parameter" {
            $CommandUnderTest | Should -HaveParameter SeedingMode -Type System.String
        }
        It "Should have Endpoint parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint -Type System.String
        }
        It "Should have EndpointUrl parameter" {
            $CommandUnderTest | Should -HaveParameter EndpointUrl -Type System.String[]
        }
        It "Should have Passthru parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru -Type System.Management.Automation.SwitchParameter
        }
        It "Should have ReadOnlyRoutingList parameter" {
            $CommandUnderTest | Should -HaveParameter ReadOnlyRoutingList -Type System.String[]
        }
        It "Should have ReadonlyRoutingConnectionUrl parameter" {
            $CommandUnderTest | Should -HaveParameter ReadonlyRoutingConnectionUrl -Type System.String
        }
        It "Should have Certificate parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate -Type System.String
        }
        It "Should have ConfigureXESession parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigureXESession -Type System.Management.Automation.SwitchParameter
        }
        It "Should have SessionTimeout parameter" {
            $CommandUnderTest | Should -HaveParameter SessionTimeout -Type System.Int32
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.AvailabilityGroup
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
