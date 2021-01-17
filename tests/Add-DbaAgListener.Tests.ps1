$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Name', 'IPAddress', 'SubnetIP', 'SubnetMask', 'Port', 'Dhcp', 'Passthru', 'InputObject', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_ag_newlistener"
        $listenerName = 'dbatoolsci_listener'
        $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }
    AfterEach {
        $null = Remove-DbaAgListener -SqlInstance $script:instance3 -Listener $listenerName -AvailabilityGroup $agname -Confirm:$false
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }
    Context "creates a listener" {
        It "returns results with proper data" {
            $results = $ag | Add-DbaAgListener -Name $listenerName -IPAddress 127.0.20.1 -Confirm:$false
            $results.PortNumber | Should -Be 1433
        }
    }
} #$script:instance2 for appveyor