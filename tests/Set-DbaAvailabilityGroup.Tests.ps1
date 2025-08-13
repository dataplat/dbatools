$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'AllAvailabilityGroups', 'DtcSupportEnabled', 'ClusterType', 'AutomatedBackupPreference', 'FailureConditionLevel', 'HealthCheckTimeout', 'BasicAvailabilityGroup', 'DatabaseHealthTrigger', 'IsDistributedAvailabilityGroup', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_agroup"
        $null = New-DbaAvailabilityGroup -Primary $TestConfig.instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }
    AfterAll {
        Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
    }
    Context "sets ag properties" {
        It "returns modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false -DtcSupportEnabled:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $false
        }
        It "returns newly modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false -DtcSupportEnabled
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $true
        }
    }
} #$TestConfig.instance2 for appveyor
