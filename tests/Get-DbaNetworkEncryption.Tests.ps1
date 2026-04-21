#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaNetworkEncryption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        BeforeAll {
            function New-MockNetworkEncryptionReadTask {
                $task = [PSCustomObject]@{ }
                Add-Member -InputObject $task -MemberType ScriptMethod -Name Wait -Value {
                    param($Timeout)

                    $true
                } -Force
                $task
            }

            function New-MockNetworkEncryptionStream {
                param(
                    [byte[]]$ReadBytes
                )

                $stream = [PSCustomObject]@{
                    Position  = 0
                    ReadBytes = $ReadBytes
                }
                Add-Member -InputObject $stream -MemberType ScriptMethod -Name Write -Value {
                    param(
                        [byte[]]$Buffer,
                        [int]$Offset,
                        [int]$Count
                    )
                } -Force
                Add-Member -InputObject $stream -MemberType ScriptMethod -Name Read -Value {
                    param(
                        [byte[]]$Buffer,
                        [int]$Offset,
                        [int]$Count
                    )

                    $remaining = $this.ReadBytes.Length - $this.Position
                    if ($remaining -le 0) {
                        return 0
                    }

                    $copyCount = [Math]::Min($Count, $remaining)
                    [Array]::Copy($this.ReadBytes, $this.Position, $Buffer, $Offset, $copyCount)
                    $this.Position += $copyCount
                    $copyCount
                } -Force
                Add-Member -InputObject $stream -MemberType ScriptMethod -Name Dispose -Value {
                } -Force
                $stream
            }

            function New-MockNetworkEncryptionUdpClient {
                $udpClient = [PSCustomObject]@{
                    Client = [PSCustomObject]@{
                        SendTimeout    = 0
                        ReceiveTimeout = 0
                    }
                }
                Add-Member -InputObject $udpClient -MemberType ScriptMethod -Name Send -Value {
                    param(
                        [byte[]]$Buffer,
                        [int]$Count
                    )

                    $Count
                } -Force
                Add-Member -InputObject $udpClient -MemberType ScriptMethod -Name Receive -Value {
                    param([ref]$RemoteEndPoint)

                    $script:sqlBrowserResponseBytes
                } -Force
                Add-Member -InputObject $udpClient -MemberType ScriptMethod -Name Dispose -Value {
                } -Force
                $udpClient
            }

            function New-MockNetworkEncryptionTcpClient {
                param(
                    $Stream
                )

                $tcpClient = [PSCustomObject]@{
                    Stream = $Stream
                }
                Add-Member -InputObject $tcpClient -MemberType ScriptMethod -Name ConnectAsync -Value {
                    param(
                        $ComputerName,
                        $Port
                    )

                    $script:tcpConnectTarget = "${ComputerName}:$Port"
                    New-MockNetworkEncryptionReadTask
                } -Force
                Add-Member -InputObject $tcpClient -MemberType ScriptMethod -Name GetStream -Value {
                    $this.Stream
                } -Force
                Add-Member -InputObject $tcpClient -MemberType ScriptMethod -Name Dispose -Value {
                } -Force
                $tcpClient
            }

            function New-MockNetworkEncryptionSslStream {
                param(
                    $RemoteCertificate
                )

                $sslStream = [PSCustomObject]@{
                    RemoteCertificate = $RemoteCertificate
                }
                Add-Member -InputObject $sslStream -MemberType ScriptMethod -Name AuthenticateAsClient -Value {
                    param($ComputerName)
                } -Force
                Add-Member -InputObject $sslStream -MemberType ScriptMethod -Name Dispose -Value {
                } -Force
                $sslStream
            }

            function Get-MockNetworkEncryptionSqlBrowserResponseBytes {
                param(
                    [string]$ComputerName,
                    [string]$InstanceName,
                    [int]$Port,
                    [string]$PipeName
                )

                $rawResponse = "ServerName;$ComputerName;InstanceName;$InstanceName;tcp;$Port;np;$PipeName;;"
                $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($rawResponse)
                $responseBytes = New-Object byte[] ($rawBytes.Length + 3)
                $responseBytes[0] = 0x05
                $lengthBytes = [System.BitConverter]::GetBytes([UInt16]$rawBytes.Length)
                $responseBytes[1] = $lengthBytes[0]
                $responseBytes[2] = $lengthBytes[1]
                [Array]::Copy($rawBytes, 0, $responseBytes, 3, $rawBytes.Length)
                $responseBytes
            }

            function Get-MockNetworkEncryptionPreLoginResponseBytes {
                [byte[]]@(
                    0x04, 0x01, 0x00, 0x0f, 0x00, 0x00, 0x01, 0x00,
                    0x01, 0x00, 0x06, 0x00, 0x01, 0xff, 0x03
                )
            }
        }

        Context "TLS helper behavior" {
            BeforeEach {
                $script:tcpConnectTarget = $null
                $script:mockCertificate = [PSCustomObject]@{
                    Subject      = "CN=sql01"
                    Issuer       = "CN=test-ca"
                    Thumbprint   = "ABC123"
                    NotAfter     = (Get-Date).AddDays(30)
                    NotBefore    = (Get-Date).AddDays(-1)
                    DnsNameList  = @("sql01")
                    SerialNumber = "123456"
                }
                $script:sqlBrowserResponseBytes = Get-MockNetworkEncryptionSqlBrowserResponseBytes -ComputerName "sql01" -InstanceName "MSSQLSERVER" -Port 1433 -PipeName "\\sql01\pipe\sql\query"
                $script:tcpStream = New-MockNetworkEncryptionStream -ReadBytes (Get-MockNetworkEncryptionPreLoginResponseBytes)

                Mock Add-Type { }
                function Write-Message {
                    param(
                        $Level,
                        $Message
                    )
                }
                Mock New-Object {
                    New-MockNetworkEncryptionUdpClient
                } -ParameterFilter {
                    $TypeName -eq "System.Net.Sockets.UdpClient"
                }
                Mock New-Object {
                    New-MockNetworkEncryptionTcpClient -Stream $script:tcpStream
                } -ParameterFilter {
                    $TypeName -eq "System.Net.Sockets.TcpClient"
                }
                Mock New-Object {
                    throw "Named pipe fallback should not be used when SQL Browser returns a TCP port."
                } -ParameterFilter {
                    $TypeName -eq "System.IO.Pipes.NamedPipeClientStream"
                }
                Mock New-Object {
                    $ArgumentList[0]
                } -ParameterFilter {
                    $TypeName -eq "TdsTlsStream"
                }
                Mock New-Object {
                    New-MockNetworkEncryptionSslStream -RemoteCertificate $script:mockCertificate
                } -ParameterFilter {
                    $TypeName -eq "System.Net.Security.SslStream"
                }
                Mock New-Object {
                    $script:mockCertificate
                } -ParameterFilter {
                    $TypeName -eq "System.Security.Cryptography.X509Certificates.X509Certificate2"
                }
            }

            It "prefers the SQL Browser TCP endpoint over named pipes" {
                $result = Get-SqlServerTlsCertificate -ComputerName "sql01" -InstanceName "MSSQLSERVER"

                $result.Thumbprint | Should -Be "ABC123"
                $script:tcpConnectTarget | Should -Be "sql01:1433"
            }

            It "throws when the TDS pre-login response header ends early" {
                $script:tcpStream = New-MockNetworkEncryptionStream -ReadBytes ([byte[]]@(0x04, 0x01, 0x00))

                {
                    Get-SqlServerTlsCertificate -ComputerName "sql01" -InstanceName "MSSQLSERVER" -ErrorAction Stop
                } | Should -Throw "*Unexpected EOF while reading the TDS pre-login response header from sql01*"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Certificate retrieval" {
        BeforeAll {
            # Attempt to retrieve the certificate - not all environments have TLS configured
            $result = Get-DbaNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
        }

        It "Should return certificate with expected properties when TLS is configured" {
            if ($null -eq $result) {
                Set-ItResult -Skipped -Because "No TLS certificate is configured on this SQL Server instance"
            }
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Subject | Should -Not -BeNullOrEmpty
            $result.Thumbprint | Should -Not -BeNullOrEmpty
            $result.Expires | Should -BeOfType [datetime]
            $result.NotBefore | Should -BeOfType [datetime]
        }
    }
}