$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Replica', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_agroup"
        $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }
    AfterAll {
        Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
    }
    Context "gets ag replicas" {
        It "returns results with proper data" {
            $results = Get-DbaAgReplica -SqlInstance $script:instance3
            $results.AvailabilityGroup | Should -Contain $agname
            $results.Role | Should -Contain 'Primary'
            $results.AvailabilityMode | Should -Contain 'SynchronousCommit'
        }
        It "returns just one result" {
            $server = Connect-DbaInstance -SqlInstance $script:instance3
            $results = Get-DbaAgReplica -SqlInstance $script:instance3 -Replica $server.DomainInstanceName -AvailabilityGroup $agname
            $results.AvailabilityGroup | Should -Be $agname
            $results.Role | Should -Be 'Primary'
            $results.AvailabilityMode | Should -Be 'SynchronousCommit'
        }
    }
} #$script:instance2 for appveyor