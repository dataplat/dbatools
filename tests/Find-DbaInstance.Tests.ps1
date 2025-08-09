#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaInstance",  # Static command name for dbatools
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command finds SQL Server instances" {
        BeforeAll {
            $results = Find-DbaInstance -ComputerName $TestConfig.instance3 -ScanType Browser, SqlConnect | Select-Object -First 1
        }

        It "Returns an object type of [Dataplat.Dbatools.Discovery.DbaInstanceReport]" {
            $results | Should -BeOfType [Dataplat.Dbatools.Discovery.DbaInstanceReport]
        }

        It "FullName is populated" {
            $results.FullName | Should -Not -BeNullOrEmpty
        }

        if (([DbaInstanceParameter]$TestConfig.instance3).IsLocalHost -eq $false) {
            It "TcpConnected is true" {
                $results.TcpConnected | Should -Be $true
            }
        }

        It "successfully connects" {
            $results.SqlConnected | Should -Be $true
        }
    }
}