#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Add-DbaAgListener" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaAgListener
            $expectedParameters = $TestConfig.CommonParameters

            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "AvailabilityGroup",
                "Name",
                "IPAddress",
                "SubnetIP",
                "SubnetMask",
                "Port",
                "Dhcp",
                "Passthru",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have exactly the expected parameters" {
            $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $actualParameters | Should -BeNullOrEmpty
        }

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }
    }
}

Describe "Add-DbaAgListener" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_ag_newlistener"
        $listenerName = 'dbatoolsci_listener'
        $splat = @{
            Primary       = $TestConfig.instance3
            Name          = $agname
            ClusterType   = "None"
            FailoverMode  = "Manual"
            Certificate   = "dbatoolsci_AGCert"
            Confirm       = $false
        }
        $ag = New-DbaAvailabilityGroup @splat
    }

    AfterEach {
        $null = Remove-DbaAgListener -SqlInstance $TestConfig.instance3 -Listener $listenerName -AvailabilityGroup $agname -Confirm:$false
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "When creating a listener" {
        It "Returns results with proper data" {
            $splat = @{
                Name          = $listenerName
                IPAddress     = "127.0.20.1"
                Port          = 14330
                Confirm       = $false
            }
            $results = $ag | Add-DbaAgListener @splat
            $results.PortNumber | Should -Be 14330
        }
    }
} #$TestConfig.instance2 for appveyor
