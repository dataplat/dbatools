#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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

    InModuleScope dbatools {
        BeforeAll {
            function New-MockFindDbaInstanceUdpClient {
                param(
                    [byte[]]$ResponseBytes
                )

                $udpClient = [PSCustomObject]@{
                    Client        = [PSCustomObject]@{
                        ReceiveTimeout = 0
                        Blocking       = $false
                    }
                    ResponseBytes = $ResponseBytes
                }
                Add-Member -InputObject $udpClient -MemberType ScriptMethod -Name Connect -Value {
                    param(
                        $ComputerName,
                        $Port
                    )
                } -Force
                Add-Member -InputObject $udpClient -MemberType ScriptMethod -Name Send -Value {
                    param(
                        [byte[]]$Buffer,
                        [int]$Count
                    )

                    $Count
                } -Force
                Add-Member -InputObject $udpClient -MemberType ScriptMethod -Name Receive -Value {
                    param([ref]$RemoteEndPoint)

                    $this.ResponseBytes
                } -Force
                Add-Member -InputObject $udpClient -MemberType ScriptMethod -Name Close -Value {
                } -Force
                $udpClient
            }

            function New-MockFindDbaInstanceTcpClient {
                $tcpClient = [PSCustomObject]@{
                    Connected = $false
                }
                Add-Member -InputObject $tcpClient -MemberType ScriptMethod -Name Connect -Value {
                    param(
                        $ComputerName,
                        $Port
                    )

                    $script:tcpConnectPorts += $Port
                    $this.Connected = $Port -in @(1433, 51433)
                } -Force
                Add-Member -InputObject $tcpClient -MemberType ScriptMethod -Name Dispose -Value {
                } -Force
                $tcpClient
            }
        }

        Context "Browser scan handling" {
            BeforeEach {
                $script:tcpConnectPorts = @()
                $script:browserResponseBytes = [System.Text.Encoding]::ASCII.GetBytes(
                    "ServerName;sqlhost;InstanceName;MSSQLSERVER;IsClustered;No;Version;16.0.1000.6;ServerName;sqlhost;InstanceName;DEV;IsClustered;No;Version;16.0.1000.6;tcp;51433"
                )

                Mock Test-FunctionInterrupt { $false }
                function Write-ProgressHelper {
                }
                function Write-Message {
                }
                Mock New-Object { & (Get-Command -Name 'New-Object' -CommandType Cmdlet) @PesterBoundParameters }
                Mock New-Object {
                    New-MockFindDbaInstanceUdpClient -ResponseBytes $script:browserResponseBytes
                } -ParameterFilter {
                    $TypeName -eq "System.Net.Sockets.UdpClient"
                }
                Mock New-Object {
                    New-MockFindDbaInstanceTcpClient
                } -ParameterFilter {
                    $TypeName -eq "Net.Sockets.TcpClient"
                }
            }

            It "scans fallback ports for default instances without reusing named instance ports" {
                $results = Find-DbaInstance -ComputerName "sqlhost" -ScanType Browser
                $defaultInstance = $results | Where-Object InstanceName -eq "MSSQLSERVER"
                $namedInstance = $results | Where-Object InstanceName -eq "DEV"

                $defaultInstance | Should -Not -BeNullOrEmpty
                $namedInstance | Should -Not -BeNullOrEmpty
                $script:tcpConnectPorts | Should -Contain 1433
                $script:tcpConnectPorts | Should -Contain 51433
                $defaultInstance.Port | Should -Be 1433
                $defaultInstance.TcpConnected | Should -Be $true
                $namedInstance.Port | Should -Be 51433
                $namedInstance.TcpConnected | Should -Be $true
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command finds SQL Server instances" {
        BeforeAll {
            $results = Find-DbaInstance -ComputerName $TestConfig.InstanceSingle -ScanType Browser, SqlConnect | Where-Object SqlInstance -eq $TestConfig.InstanceSingle
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
}