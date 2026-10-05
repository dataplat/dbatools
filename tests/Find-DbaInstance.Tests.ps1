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

    Context "When the pipeline is stopped" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The pipeline is stopped as soon as the scan of
            # the computer starts, which is what Ctrl+C does. The runspace imports the manifest: an import of
            # the psm1 without a command line skips the type data.
            $splatStopScan = @{
                ComputerName = $TestConfig.InstanceSingle
                ScanType     = "Browser", "SqlConnect"
            }
            if ($TestConfig.SqlCred) {
                $splatStopScan.SqlCredential = $TestConfig.SqlCred
            }
            $stopRunspace = [runspacefactory]::CreateRunspace()
            $stopRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $stopRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $stopShell = [powershell]::Create()
            $stopShell.Runspace = $stopRunspace
            $null = $stopShell.AddCommand("Find-DbaInstance").AddParameters($splatStopScan)
            $stopAsync = $stopShell.BeginInvoke()
            $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not ($stopShell.Streams.Progress | Where-Object Activity -like "Processing: *") -and -not $stopAsync.IsCompleted -and $stopWatch.Elapsed.TotalSeconds -lt 60) {
                Start-Sleep -Milliseconds 10
            }
            $stopShell.Stop()
            $stopState = $stopShell.InvocationStateInfo.State
            $stopRecords = @($stopShell.Streams.Progress)
            $stopShell.Dispose()
            $stopRunspace.Dispose()
        }

        It "Was stopped while it was running" {
            $stopState | Should -Be "Stopped"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $stopRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $stopRecords | Where-Object Activity -like "Processing: *" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}