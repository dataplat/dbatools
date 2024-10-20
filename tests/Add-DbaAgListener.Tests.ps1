param($ModuleName = 'dbatools')

Describe "Add-DbaAgListener" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Add-DbaAgListener
        }
        $paramList = @(
            'SqlInstance',
            'SqlCredential',
            'AvailabilityGroup',
            'Name',
            'IPAddress',
            'SubnetIP',
            'SubnetMask',
            'Port',
            'Dhcp',
            'Passthru',
            'InputObject',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $agname = "dbatoolsci_ag_newlistener"
            $listenerName = 'dbatoolsci_listener'
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
        }
        AfterAll {
            Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
        }

        It "creates a listener and returns results with proper data" {
            $results = $ag | Add-DbaAgListener -Name $listenerName -IPAddress 127.0.20.1 -Port 14330 -Confirm:$false
            $results.PortNumber | Should -Be 14330

            # Cleanup
            Remove-DbaAgListener -SqlInstance $global:instance3 -Listener $listenerName -AvailabilityGroup $agname -Confirm:$false
        }
    } #$global:instance2 for appveyor
}
