#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName               = "dbatools",
    $CommandName              = "Add-DbaAgListener",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
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

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # To add a listener to an availablity group, we need an availability group, an ip address and a port.
        # TODO: Add some negative tests.

        $agName = "addagdb_group"
        $listenerName = "listener"
        $listenerIp = "127.0.20.1"
        $listenerPort = 14330

        $splatAg = @{
            Primary      = $TestConfig.instance3
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
            Confirm      = $false
        }
        $ag = New-DbaAvailabilityGroup @splatAg
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -Confirm:$false
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false

        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "When creating a listener" {
        BeforeAll {
            $splatListener = @{
                Name      = $listenerName
                IPAddress = $listenerIp
                Port      = $listenerPort
            }
            $results = $ag | Add-DbaAgListener @splatListener
        }

        It "Does not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Returns results with proper data" {
            $results.PortNumber | Should -Be $listenerPort
        }
    }
} #$TestConfig.instance2 for appveyor
