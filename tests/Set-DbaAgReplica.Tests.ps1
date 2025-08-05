$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Replica', 'AvailabilityMode', 'FailoverMode', 'BackupPriority', 'ConnectionModeInPrimaryRole', 'ConnectionModeInSecondaryRole', 'SeedingMode', 'SessionTimeout', 'EndpointUrl', 'ReadonlyRoutingConnectionUrl', 'ReadOnlyRoutingList', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_arepgroup"
        $ag = New-DbaAvailabilityGroup -Primary $TestConfig.instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
        $replicaName = $ag.PrimaryReplica
    }
    AfterAll {
        Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
    }
    Context "sets ag properties" {
        It "returns modified results" {
            $results = Set-DbaAgReplica -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Replica $replicaName -BackupPriority 100 -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.BackupPriority | Should -Be 100
        }
        It "returns modified results" {
            $results = Set-DbaAgReplica -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Replica $replicaName -SeedingMode Automatic -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.SeedingMode | Should -Be Automatic
        }
        It "attempts to add a ReadOnlyRoutingList" {
            $null = Get-DbaAgReplica -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname | Select-Object -First 1 | Set-DbaAgReplica -ReadOnlyRoutingList nondockersql -WarningAction SilentlyContinue -WarningVariable warn -Confirm:$false
            $warn | Should -match "does not exist. Only availability"
        }
    }
} #$TestConfig.instance2 for appveyor

