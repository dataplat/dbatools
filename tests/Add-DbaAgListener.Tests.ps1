#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Add-DbaAgListener" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaAgListener
            $expected = $TestConfig.CommonParameters

            $expected += @(
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

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Add-DbaAgListener" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_ag_newlistener"
        $listenerName = 'dbatoolsci_listener'
        $splatNewAg = @{
            Primary = $TestConfig.instance3
            Name = $agname
            ClusterType = "None"
            FailoverMode = "Manual"
            Confirm = $false
            Certificate = "dbatoolsci_AGCert"
        }
        $ag = New-DbaAvailabilityGroup @splatNewAg
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "When creating a listener" {
        BeforeAll {
            $splatAddListener = @{
                Name = $listenerName
                IPAddress = "127.0.20.1"
                Port = 14330
                Confirm = $false
            }
            $results = $ag | Add-DbaAgListener @splatAddListener
        }

        AfterAll {
            $null = Remove-DbaAgListener -SqlInstance $TestConfig.instance3 -Listener $listenerName -AvailabilityGroup $agname -Confirm:$false
        }

        It "Returns results with proper data" {
            $results.PortNumber | Should -Be 14330
        }
    }
} #$TestConfig.instance2 for appveyor
