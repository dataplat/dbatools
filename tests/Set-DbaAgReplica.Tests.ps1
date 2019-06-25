$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Replica', 'AvailabilityMode', 'FailoverMode', 'BackupPriority', 'ConnectionModeInPrimaryRole', 'ConnectionModeInSecondaryRole', 'SeedingMode', 'EndpointUrl', 'ReadonlyRoutingConnectionUrl', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_arepgroup"
        $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }
    AfterAll {
        Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }
    Context "sets ag properties" {
        It "returns modified results" {
            $results = Set-DbaAgReplica -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false -BackupPriority 5000
            $results.AvailabilityGroup | Should -Be $agname
            $results.BackupPriority | Should -Be 5000
        }
        It "returns modified results" {
            $results = Set-DbaAgReplica -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false -BackupPriority 1000
            $results.AvailabilityGroup | Should -Be $agname
            $results.BackupPriority | Should -Be 1000
        }
    }
} #$script:instance2 for appveyor