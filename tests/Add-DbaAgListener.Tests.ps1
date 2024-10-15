param($ModuleName = 'dbatools')

Describe "Add-DbaAgListener Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Import the function
        . (Join-Path -Path $PSScriptRoot -ChildPath '..\functions\Add-DbaAgListener.ps1')
    }

    Context "Validate parameters" {
        BeforeDiscovery {
            $commandInfo = Get-Command Add-DbaAgListener
            $parameterInfo = $commandInfo.Parameters
        }

        It "Should have parameter <_>" -ForEach @(
            'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Name', 'IPAddress', 'SubnetIP', 'SubnetMask',
            'Port', 'Dhcp', 'Passthru', 'InputObject', 'EnableException'
        ) {
            $parameterInfo.ContainsKey($_) | Should -Be $true
        }

        It "SqlInstance parameter should be mandatory" {
            $parameterInfo['SqlInstance'].Attributes.Mandatory | Should -Be $true
        }

        It "Port parameter should have a default value of 1433" {
            $parameterInfo['Port'].DefaultValue | Should -Be 1433
        }
    }
}

Describe "Add-DbaAgListener Integration Tests" -Tag "IntegrationTests" {
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

    It "creates a listener" {
        $results = $ag | Add-DbaAgListener -Name $listenerName -IPAddress 127.0.20.1 -Port 14330 -Confirm:$false
        $results.PortNumber | Should -Be 14330
    }
}

#$script:instance2 for appveyor
