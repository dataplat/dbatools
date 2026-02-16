#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "DiscoveryType",
                "Credential",
                "SqlCredential",
                "ScanType",
                "IpAddress",
                "DomainController",
                "TCPPort",
                "MinimumConfidence",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command finds SQL Server instances" {
        BeforeAll {
            $results = Find-DbaInstance -ComputerName $TestConfig.InstanceSingle -ScanType Browser, SqlConnect -OutVariable "global:dbatoolsciOutput" | Where-Object SqlInstance -eq $TestConfig.InstanceSingle
        }

        It "Returns an object type of [Dataplat.Dbatools.Discovery.DbaInstanceReport]" {
            $results | Should -BeOfType [Dataplat.Dbatools.Discovery.DbaInstanceReport]
        }

        It "FullName is populated" {
            $results.FullName | Should -Not -BeNullOrEmpty
        }

        if (([DbaInstanceParameter]$TestConfig.InstanceSingle).IsLocalHost -eq $false) {
            It "TcpConnected is true" {
                $results.TcpConnected | Should -Be $true
            }
        }

        It "successfully connects" {
            $results.SqlConnected | Should -Be $true
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Dataplat.Dbatools.Discovery.DbaInstanceReport]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "MachineName",
                "ComputerName",
                "InstanceName",
                "FullName",
                "SqlInstance",
                "Port",
                "TcpConnected",
                "SqlConnected",
                "DnsResolution",
                "Ping",
                "BrowseReply",
                "Services",
                "SystemServices",
                "SPNs",
                "PortsScanned",
                "Availability",
                "Confidence",
                "ScanTypes",
                "Timestamp"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Dataplat\.Dbatools\.Discovery\.DbaInstanceReport"
        }
    }
}