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
            $results = Find-DbaInstance -ComputerName $TestConfig.InstanceSingle -ScanType Browser, SqlConnect | Select-Object -First 1
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

    Context "Output Validation" {
        BeforeAll {
            $result = Find-DbaInstance -ComputerName $TestConfig.InstanceSingle -ScanType Browser, SqlConnect -EnableException | Select-Object -First 1
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Dataplat.Dbatools.Discovery.DbaInstanceReport]
        }

        It "Has core identification properties" {
            $coreProps = @(
                'MachineName',
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Port'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $coreProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should exist"
            }
        }

        It "Has discovery metadata properties" {
            $metadataProps = @(
                'Confidence',
                'Availability',
                'Timestamp',
                'ScanTypes'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $metadataProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should exist"
            }
        }

        It "Has connectivity test properties" {
            $connectivityProps = @(
                'DnsResolution',
                'Ping',
                'TcpConnected',
                'SqlConnected'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $connectivityProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should exist"
            }
        }

        It "Has discovery detail properties" {
            $detailProps = @(
                'Services',
                'SystemServices',
                'SPNs',
                'BrowseReply',
                'PortsScanned'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $detailProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should exist"
            }
        }
    }
}