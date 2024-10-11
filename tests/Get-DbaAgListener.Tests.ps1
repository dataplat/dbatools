$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Listener', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_ag_listener"
        $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert
        $ag | Add-DbaAgListener -IPAddress 127.0.20.1 -Port 14330
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname
    }
    Context "gets ags" {
        It "returns results with proper data" {
            $results = Get-DbaAgListener -SqlInstance $script:instance3
            $results.PortNumber | Should -Contain 14330
        }
    }
} #$script:instance2 for appveyor