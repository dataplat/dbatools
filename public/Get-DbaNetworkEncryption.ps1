function Get-DbaNetworkEncryption {
    <#
    .SYNOPSIS
        Retrieves the SSL/TLS certificate presented by SQL Server over the network connection.

    .DESCRIPTION
        Connects to a SQL Server instance over the network and retrieves the SSL/TLS certificate that the server presents during the TLS handshake, without requiring Windows host access or WinRM connectivity.

        This is useful when you need to verify which certificate SQL Server is presenting to clients, check certificate expiration dates, or audit SSL/TLS configurations across environments where you don't have Windows-level access.

        Unlike Get-DbaNetworkCertificate which reads the configured certificate from the Windows registry (requiring WinRM), this command connects directly to the SQL Server network port and retrieves the certificate presented during the SSL/TLS handshake.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be specified as hostname, hostname\instance, or hostname:port.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Encryption, Security, Network, SSL, TLS
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaNetworkEncryption

    .EXAMPLE
        PS C:\> Get-DbaNetworkEncryption -SqlInstance sql2016

        Retrieves the SSL/TLS certificate presented by the default SQL Server instance on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaNetworkEncryption -SqlInstance sql2016\sqlexpress

        Retrieves the SSL/TLS certificate presented by the named instance SQLEXPRESS on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaNetworkEncryption -SqlInstance sql2016:14331

        Retrieves the SSL/TLS certificate presented by SQL Server listening on port 14331.

    .EXAMPLE
        PS C:\> Get-DbaNetworkEncryption -SqlInstance sql2016, sql2017, sql2019

        Retrieves the SSL/TLS certificates from multiple SQL Server instances.

    .EXAMPLE
        PS C:\> Get-DbaNetworkEncryption -SqlInstance sql2016 | Select-Object SqlInstance, Subject, Expires, Thumbprint

        Retrieves the certificate and displays specific properties including expiration date and thumbprint.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    begin {
        $certValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback] {
            param($sender, $certificate, $chain, $sslPolicyErrors)
            return $true
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Processing $instance"

                $server = $null
                $tcpClient = $null
                $sslStream = $null

                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9

                    $hostname = $server.ComputerName
                    $port = $server.TcpPort

                    if (-not $port) {
                        if ($instance.InstanceName -eq "MSSQLSERVER") {
                            $port = 1433
                        } else {
                            $udpClient = $null
                            try {
                                Write-Message -Level Verbose -Message "Querying SQL Browser for port information"
                                $udpClient = New-Object System.Net.Sockets.UdpClient
                                $udpClient.Client.ReceiveTimeout = 1000

                                $instanceBytes = [System.Text.Encoding]::ASCII.GetBytes($instance.InstanceName)
                                $requestPacket = New-Object System.Collections.ArrayList
                                $null = $requestPacket.Add(0x04)
                                $null = $requestPacket.AddRange($instanceBytes)

                                $endPoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse($hostname), 1434)
                                $null = $udpClient.Send($requestPacket.ToArray(), $requestPacket.Count, $endPoint)

                                $responseEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                                $response = $udpClient.Receive([ref]$responseEndpoint)
                                $responseString = [System.Text.Encoding]::ASCII.GetString($response)

                                if ($responseString -match "tcp;(\d+)") {
                                    $port = $matches[1]
                                    Write-Message -Level Verbose -Message "Found port $port from SQL Browser"
                                }
                            } catch {
                                Write-Message -Level Warning -Message "Failed to query SQL Browser: $_"
                            } finally {
                                if ($udpClient) {
                                    $udpClient.Close()
                                    $udpClient.Dispose()
                                }
                            }

                            if (-not $port) {
                                $port = 1433
                                Write-Message -Level Verbose -Message "Falling back to default port 1433"
                            }
                        }
                    }

                    Write-Message -Level Verbose -Message "Connecting to $hostname`:$port"

                    $tcpClient = New-Object System.Net.Sockets.TcpClient
                    $tcpClient.Connect($hostname, $port)

                    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $certValidationCallback)

                    $sslStream.AuthenticateAsClient($hostname)

                    $certificate = $sslStream.RemoteCertificate

                    if ($certificate) {
                        $x509cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificate)

                        $dnsNames = New-Object System.Collections.ArrayList
                        foreach ($extension in $x509cert.Extensions) {
                            if ($extension.Oid.Value -eq "2.5.29.17") {
                                $sanExtension = New-Object System.Security.Cryptography.X509Certificates.X509Extension($extension, $false)
                                $asnData = New-Object System.Security.Cryptography.AsnEncodedData($sanExtension.Oid, $sanExtension.RawData)
                                $sanString = $asnData.Format($false)
                                foreach ($line in $sanString -split "`n") {
                                    if ($line -match "DNS Name=(.+)") {
                                        $null = $dnsNames.Add($matches[1].Trim())
                                    }
                                }
                            }
                        }

                        [PSCustomObject]@{
                            ComputerName     = $server.ComputerName
                            InstanceName     = $server.InstanceName
                            SqlInstance      = $server.DomainInstanceName
                            Port             = $port
                            Subject          = $x509cert.Subject
                            Issuer           = $x509cert.Issuer
                            FriendlyName     = $x509cert.FriendlyName
                            DnsNameList      = $dnsNames
                            Thumbprint       = $x509cert.Thumbprint
                            SerialNumber     = $x509cert.SerialNumber
                            NotBefore        = $x509cert.NotBefore
                            NotAfter         = $x509cert.NotAfter
                            Expires          = $x509cert.NotAfter
                            HasPrivateKey    = $x509cert.HasPrivateKey
                            Version          = $x509cert.Version
                            SignatureAlgorithm = $x509cert.SignatureAlgorithm.FriendlyName
                            Certificate      = $x509cert
                        } | Select-DefaultView -Property "ComputerName", "InstanceName", "SqlInstance", "Subject", "Issuer", "Thumbprint", "NotBefore", "NotAfter"
                    } else {
                        Stop-Function -Message "No certificate was presented by $instance" -Target $instance -Continue
                    }
                } finally {
                    if ($sslStream) {
                        $sslStream.Close()
                        $sslStream.Dispose()
                    }
                    if ($tcpClient) {
                        $tcpClient.Close()
                        $tcpClient.Dispose()
                    }
                }
            } catch {
                Stop-Function -Message "Failed to retrieve certificate from $instance" -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}
