$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'AllAvailabilityGroups', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_removewholegroup"
        $null = New-DbaAvailabilityGroup -Primary $TestConfig.instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
    }
    Context "removes the newly created ag" {
        It "removes the ag" {
            $results = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false -WarningVariable warn
            $warn | Should -BeNullorEmpty
            $results.Status | Should -Be 'Removed'
            $results.AvailabilityGroup | Should -Be $agname
            $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        }
        It "really removed the ag" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname
            $results | Should -BeNullorEmpty
        }
    }
} #$TestConfig.instance2 for appveyor