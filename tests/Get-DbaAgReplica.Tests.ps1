param($ModuleName = 'dbatools')

Describe "Get-DbaAgReplica" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgReplica
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "AvailabilityGroup",
            "Replica",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            $agname = "dbatoolsci_agroup"
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
            $replicaName = $ag.PrimaryReplica
        }
        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
        }
        It "returns results with proper data" {
            $results = Get-DbaAgReplica -SqlInstance $global:instance3
            $results.AvailabilityGroup | Should -Contain $agname
            $results.Role | Should -Contain 'Primary'
            $results.AvailabilityMode | Should -Contain 'SynchronousCommit'
        }
        It "returns just one result" {
            $results = Get-DbaAgReplica -SqlInstance $global:instance3 -Replica $replicaName -AvailabilityGroup $agname
            $results.AvailabilityGroup | Should -Be $agname
            $results.Role | Should -Be 'Primary'
            $results.AvailabilityMode | Should -Be 'SynchronousCommit'
        }

        It "Passes EnableException to Get-DbaAvailabilityGroup" -Skip {
            $results = Get-DbaAgReplica -SqlInstance invalidSQLHostName -ErrorVariable agerror
            $results | Should -BeNullOrEmpty
            ($agerror | Where-Object Message -match "The network path was not found") | Should -Not -BeNullOrEmpty

            { Get-DbaAgReplica -SqlInstance invalidSQLHostName -EnableException } | Should -Throw
        }
    }
} #$global:instance2 for appveyor
