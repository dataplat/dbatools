param($ModuleName = 'dbatools')

Describe "Set-DbaAgReplica" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgReplica
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have AvailabilityGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String
        }
        It "Should have Replica as a parameter" {
            $CommandUnderTest | Should -HaveParameter Replica -Type String
        }
        It "Should have AvailabilityMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityMode -Type String
        }
        It "Should have FailoverMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter FailoverMode -Type String
        }
        It "Should have BackupPriority as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupPriority -Type Int32
        }
        It "Should have ConnectionModeInPrimaryRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInPrimaryRole -Type String
        }
        It "Should have ConnectionModeInSecondaryRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInSecondaryRole -Type String
        }
        It "Should have SeedingMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter SeedingMode -Type String
        }
        It "Should have SessionTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter SessionTimeout -Type Int32
        }
        It "Should have EndpointUrl as a parameter" {
            $CommandUnderTest | Should -HaveParameter EndpointUrl -Type String
        }
        It "Should have ReadonlyRoutingConnectionUrl as a parameter" {
            $CommandUnderTest | Should -HaveParameter ReadonlyRoutingConnectionUrl -Type String
        }
        It "Should have ReadOnlyRoutingList as a parameter" {
            $CommandUnderTest | Should -HaveParameter ReadOnlyRoutingList -Type Object[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type AvailabilityReplica
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            $agname = "dbatoolsci_arepgroup"
            $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
            $replicaName = $ag.PrimaryReplica
        }
        AfterAll {
            Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
        }
        It "returns modified results for BackupPriority" {
            $results = Set-DbaAgReplica -SqlInstance $script:instance3 -AvailabilityGroup $agname -Replica $replicaName -BackupPriority 100 -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.BackupPriority | Should -Be 100
        }
        It "returns modified results for SeedingMode" {
            $results = Set-DbaAgReplica -SqlInstance $script:instance3 -AvailabilityGroup $agname -Replica $replicaName -SeedingMode Automatic -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.SeedingMode | Should -Be Automatic
        }
        It "attempts to add a ReadOnlyRoutingList" {
            $null = Get-DbaAgReplica -SqlInstance $script:instance3 -AvailabilityGroup $agname | 
                Select-Object -First 1 | 
                Set-DbaAgReplica -ReadOnlyRoutingList nondockersql -WarningAction SilentlyContinue -WarningVariable warn -Confirm:$false
            $warn | Should -Match "does not exist. Only availability"
        }
    }
} #$script:instance2 for appveyor
