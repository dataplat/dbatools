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
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "AvailabilityGroup",
                "Replica",
                "AvailabilityMode",
                "FailoverMode",
                "BackupPriority",
                "ConnectionModeInPrimaryRole",
                "ConnectionModeInSecondaryRole",
                "SeedingMode",
                "SessionTimeout",
                "EndpointUrl",
                "ReadonlyRoutingConnectionUrl",
                "ReadOnlyRoutingList",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $agname = "dbatoolsci_arepgroup"
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
            $replicaName = $ag.PrimaryReplica
        }
        AfterAll {
            Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
        }
        It "returns modified results for BackupPriority" {
            $results = Set-DbaAgReplica -SqlInstance $global:instance3 -AvailabilityGroup $agname -Replica $replicaName -BackupPriority 100 -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.BackupPriority | Should -Be 100
        }
        It "returns modified results for SeedingMode" {
            $results = Set-DbaAgReplica -SqlInstance $global:instance3 -AvailabilityGroup $agname -Replica $replicaName -SeedingMode Automatic -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.SeedingMode | Should -Be Automatic
        }
        It "attempts to add a ReadOnlyRoutingList" {
            $null = Get-DbaAgReplica -SqlInstance $global:instance3 -AvailabilityGroup $agname |
                Select-Object -First 1 |
                Set-DbaAgReplica -ReadOnlyRoutingList nondockersql -WarningAction SilentlyContinue -WarningVariable warn -Confirm:$false
            $warn | Should -Match "does not exist. Only availability"
        }
    }
} #$global:instance2 for appveyor
