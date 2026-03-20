function Get-DbaNetworkEncryption {
    <#
    .SYNOPSIS
        Retrieves the TLS/SSL certificate presented by a SQL Server instance over the network.

    .DESCRIPTION
        Connects directly to a SQL Server instance's TCP port and retrieves the TLS/SSL certificate
        that the server presents during the TLS handshake. This does not require Windows host access
        or WinRM - it works purely over the network like a client connecting to SQL Server.

        This complements Get-DbaNetworkCertificate, which reads the configured certificate from the
        Windows registry (requires WinRM). This command instead shows what certificate is actually
        being presented to clients over the network, without requiring any host-level access.

        For named instances, the SQL Browser service is queried on UDP port 1434 to determine the
        TCP port number. For default instances, port 1433 is used unless overridden.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Accepts pipeline input.

    .PARAMETER SqlCredential
        Not used by this command - included for pipeline compatibility. Authentication is not
        required since this command connects at the TLS layer before SQL Server authentication.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Encryption, Security, Network
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2024 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaNetworkEncryption

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance that successfully presents a TLS certificate.

        Properties:
        - ComputerName: The hostname of the SQL Server
        - InstanceName: The SQL Server instance name (MSSQLSERVER for default)
        - SqlInstance: The full SQL Server instance identifier
        - Port: The TCP port used to connect
        - Subject: The certificate subject (Common Name)
        - Issuer: The certificate issuer
        - Thumbprint: SHA-1 hash thumbprint of the certificate
        - NotBefore: DateTime when the certificate becomes valid
        - Expires: DateTime when the certificate expires
        - DnsNameList: Array of DNS names from the Subject Alternative Names extension
        - SerialNumber: Certificate serial number
        - Certificate: The full X509Certificate2 object

    .EXAMPLE
        PS C:\> Get-DbaNetworkEncryption -SqlInstance sql2016

        Retrieves the TLS certificate presented by the default SQL Server instance on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaNetworkEncryption -SqlInstance sql2016\sqlexpress

        Retrieves the TLS certificate presented by the named instance sqlexpress on sql2016.
        Queries the SQL Browser service to determine the port.

    .EXAMPLE
        PS C:\> Get-DbaNetworkEncryption -SqlInstance sql2016, sql2017, sql2019 | Select-Object SqlInstance, Subject, Expires, Thumbprint

        Retrieves certificates from multiple SQL Server instances and shows key certificate details.

    .EXAMPLE
        PS C:\> $servers | Get-DbaNetworkEncryption | Where-Object { $_.Expires -lt (Get-Date).AddDays(30) }

        Finds SQL Server instances whose TLS certificates expire within the next 30 days.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {
        # SQL Server wraps TLS handshake messages inside TDS packets (type 0x12) during negotiation.
        # This helper stream transparently adds/strips TDS framing so that SslStream can perform
        # the TLS handshake correctly over the SQL Server pre-login channel.
        if (-not ('DbaTools.TdsWrappingStream' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.IO;

namespace DbaTools {
    public class TdsWrappingStream : Stream {
        private Stream _inner;
        private byte _packetType;
        private byte _packetId;
        private byte[] _readBuffer;
        private int _readPos;
        private int _readCount;

        public TdsWrappingStream(Stream inner, byte packetType) {
            _inner = inner;
            _packetType = packetType;
            _packetId = 1;
            _readBuffer = null;
            _readPos = 0;
            _readCount = 0;
        }

        public override bool CanRead  { get { return true; } }
        public override bool CanWrite { get { return true; } }
        public override bool CanSeek  { get { return false; } }
        public override long Length   { get { throw new NotSupportedException(); } }
        public override long Position {
            get { throw new NotSupportedException(); }
            set { throw new NotSupportedException(); }
        }

        public override void Flush() { _inner.Flush(); }

        // Wrap outgoing data in TDS packet(s) before sending to SQL Server.
        public override void Write(byte[] buffer, int offset, int count) {
            int maxPayload = 32760;
            int remaining  = count;
            int srcOffset  = offset;
            while (remaining > 0) {
                int  chunkSize = remaining < maxPayload ? remaining : maxPayload;
                bool isLast    = (remaining - chunkSize) == 0;
                int  packetLen = chunkSize + 8;
                byte[] header  = new byte[] {
                    _packetType,
                    isLast ? (byte)0x01 : (byte)0x00,
                    (byte)(packetLen >> 8),
                    (byte)(packetLen & 0xFF),
                    0x00, 0x00,
                    _packetId++,
                    0x00
                };
                _inner.Write(header, 0, 8);
                _inner.Write(buffer, srcOffset, chunkSize);
                srcOffset += chunkSize;
                remaining -= chunkSize;
            }
        }

        // Strip TDS packet framing from incoming data before delivering to SslStream.
        public override int Read(byte[] buffer, int offset, int count) {
            // Return buffered payload from the previous TDS packet first.
            if (_readBuffer != null && _readPos < _readCount) {
                int available = _readCount - _readPos;
                int toCopy    = available < count ? available : count;
                Array.Copy(_readBuffer, _readPos, buffer, offset, toCopy);
                _readPos += toCopy;
                return toCopy;
            }
            // Read the 8-byte TDS header of the next packet.
            byte[] header    = new byte[8];
            int    headerRead = 0;
            while (headerRead < 8) {
                int n = _inner.Read(header, headerRead, 8 - headerRead);
                if (n == 0) return 0;
                headerRead += n;
            }
            int payloadLen = ((header[2] << 8) | header[3]) - 8;
            if (payloadLen <= 0) return 0;
            // Read the full payload.
            _readBuffer = new byte[payloadLen];
            _readCount  = 0;
            while (_readCount < payloadLen) {
                int n = _inner.Read(_readBuffer, _readCount, payloadLen - _readCount);
                if (n == 0) break;
                _readCount += n;
            }
            _readPos = 0;
            int toCopyNow = _readCount < count ? _readCount : count;
            Array.Copy(_readBuffer, 0, buffer, offset, toCopyNow);
            _readPos = toCopyNow;
            return toCopyNow;
        }

        public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
        public override void SetLength(long value)                 { throw new NotSupportedException(); }
    }
}
"@
        }

        function Get-SqlBrowserPort {
            param (
                [string]$ComputerName,
                [string]$InstanceName
            )
            try {
                $udpClient = New-Object System.Net.Sockets.UdpClient
                $udpClient.Client.ReceiveTimeout = 3000
                $udpClient.Client.SendTimeout = 3000

                # Resolve hostname to IP address for UdpClient
                $hostEntry = [System.Net.Dns]::GetHostEntry($ComputerName)
                $ipAddress = $hostEntry.AddressList | Where-Object {
                    $PSItem.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
                } | Select-Object -First 1

                if ($null -eq $ipAddress) {
                    $ipAddress = $hostEntry.AddressList | Select-Object -First 1
                }

                $endPoint = New-Object System.Net.IPEndPoint($ipAddress, 1434)

                # SQL Browser single-instance query: 0x04 followed by the instance name
                $instanceBytes = [System.Text.Encoding]::ASCII.GetBytes($InstanceName)
                $queryBytes = New-Object byte[] ($instanceBytes.Length + 1)
                $queryBytes[0] = 0x04
                [System.Array]::Copy($instanceBytes, 0, $queryBytes, 1, $instanceBytes.Length)

                $null = $udpClient.Send($queryBytes, $queryBytes.Length, $endPoint)
                $receiveEndPoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                $responseBytes = $udpClient.Receive([ref]$receiveEndPoint)
                $udpClient.Close()

                $responseText = [System.Text.Encoding]::ASCII.GetString($responseBytes)

                # Parse the response: key=value;key=value;...
                if ($responseText -match "tcp;(\d+)") {
                    return [int]$matches[1]
                }
            } catch {
                Write-Message -Level Debug -Message "Failed to query SQL Browser on $ComputerName for instance $InstanceName`: $_"
            } finally {
                if ($null -ne $udpClient) {
                    try { $udpClient.Close() } catch { }
                }
            }
            return $null
        }

        function Get-TlsCertificate {
            param (
                [string]$ComputerName,
                [int]$Port,
                [string]$TargetHost
            )
            $tcpClient = $null
            $sslStream = $null

            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $tcpClient.ReceiveTimeout = 5000
                $tcpClient.SendTimeout = 5000

                $connectResult = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
                $waited = $connectResult.AsyncWaitHandle.WaitOne(5000, $false)

                if (-not $waited) {
                    throw "Connection timed out to ${ComputerName}:${Port}"
                }

                $tcpClient.EndConnect($connectResult)

                if (-not $tcpClient.Connected) {
                    throw "Failed to connect to ${ComputerName}:${Port}"
                }

                $networkStream = $tcpClient.GetStream()

                # Send a SQL Server pre-login packet requesting ENCRYPT_ON (0x01).
                # SQL Server uses STARTTLS-style negotiation: TLS only starts after this exchange.
                # Pre-login packet layout (26 bytes total):
                #   TDS header (8 bytes): type=0x12 (PRE_LOGIN), status=0x01 (EOM), length=0x001A (26)
                #   Payload option headers (11 bytes):
                #     VERSION    (type=0x00): data-offset=11 (0x000B), data-length=6 (0x0006)
                #     ENCRYPTION (type=0x01): data-offset=17 (0x0011), data-length=1 (0x0001)
                #     TERMINATOR (0xFF)
                #   Payload data (7 bytes):
                #     VERSION data    at payload offset 11: major=8, minor=0, build=0, subbuild=0
                #     ENCRYPTION data at payload offset 17: 0x01 = ENCRYPT_ON
                $preLoginBytes = [byte[]](
                    0x12, 0x01, 0x00, 0x1A, 0x00, 0x00, 0x01, 0x00, # TDS header
                    0x00, 0x00, 0x0B, 0x00, 0x06,                   # VERSION: type=0, offset=11, length=6
                    0x01, 0x00, 0x11, 0x00, 0x01,                   # ENCRYPTION: type=1, offset=17, length=1
                    0xFF,                                           # TERMINATOR
                    0x08, 0x00, 0x00, 0x00, 0x00, 0x00,            # VERSION data: 8.0.0.0
                    0x01                                            # ENCRYPTION: ENCRYPT_ON
                )

                $networkStream.Write($preLoginBytes, 0, $preLoginBytes.Length)
                $networkStream.Flush()

                # Read the pre-login response
                $responseBuffer = New-Object byte[] 4096
                $bytesRead = $networkStream.Read($responseBuffer, 0, $responseBuffer.Length)

                if ($bytesRead -lt 8) {
                    throw "Invalid pre-login response from ${ComputerName}:${Port}"
                }

                # Parse the ENCRYPTION option from the server's pre-login response.
                # Option offsets in the payload are relative to the start of the payload (byte 8).
                $payloadStart = 8
                $optionOffset = $payloadStart
                $serverEncryption = $null
                while ($optionOffset -lt ($bytesRead - 4)) {
                    $optionType = $responseBuffer[$optionOffset]
                    if ($optionType -eq 0xFF) { break } # TERMINATOR
                    $dataOffset = ($responseBuffer[$optionOffset + 1] -shl 8) -bor $responseBuffer[$optionOffset + 2]
                    $dataLength = ($responseBuffer[$optionOffset + 3] -shl 8) -bor $responseBuffer[$optionOffset + 4]
                    if ($optionType -eq 0x01) {
                        # ENCRYPTION option
                        $absoluteDataOffset = $payloadStart + $dataOffset
                        if ($absoluteDataOffset -lt $bytesRead) {
                            $serverEncryption = $responseBuffer[$absoluteDataOffset]
                        }
                        break
                    }
                    $optionOffset += 5
                }

                if ($serverEncryption -eq 0x02) {
                    # ENCRYPT_NOT_SUP - server does not support TLS at all
                    throw "Server does not support TLS encryption - no certificate is presented"
                }

                # SQL Server wraps TLS handshake messages in TDS packets (type 0x12).
                # TdsWrappingStream adds/strips that framing so SslStream negotiates correctly.
                $tdsStream = New-Object DbaTools.TdsWrappingStream($networkStream, [byte]0x12)

                # Use a validation callback that always accepts the certificate so we can
                # complete the handshake regardless of chain/policy errors, then read
                # RemoteCertificate from the stream after authentication.
                $certValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback] {
                    param($sender, $certificate, $chain, $sslPolicyErrors)
                    return $true
                }

                $sslStream = New-Object System.Net.Security.SslStream(
                    $tdsStream,
                    $false,
                    $certValidationCallback
                )

                $sslStream.AuthenticateAsClient($TargetHost)

                # RemoteCertificate is the reliable way to retrieve the server certificate
                # after a successful TLS handshake.
                return $sslStream.RemoteCertificate
            } catch {
                throw
            } finally {
                if ($null -ne $sslStream) {
                    try { $sslStream.Close() } catch { }
                }
                if ($null -ne $tcpClient) {
                    try { $tcpClient.Close() } catch { }
                }
            }
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $computerName = $instance.ComputerName
            $instanceName = $instance.InstanceName
            $sqlInstanceName = $instance.FullName

            # Determine port
            $port = $instance.Port
            if ($port -le 0 -or $null -eq $port) {
                if ($instanceName -and $instanceName -ne "MSSQLSERVER") {
                    # Named instance - query SQL Browser
                    Write-Message -Level Verbose -Message "Querying SQL Browser for $instanceName on $computerName"
                    $port = Get-SqlBrowserPort -ComputerName $computerName -InstanceName $instanceName
                    if ($null -eq $port) {
                        Write-Message -Level Warning -Message "Failed to query SQL Browser for $sqlInstanceName - trying default port 1433"
                        $port = 1433
                    }
                } else {
                    $port = 1433
                }
            }

            Write-Message -Level Verbose -Message "Connecting to $computerName on port $port to retrieve TLS certificate"

            try {
                $rawCert = Get-TlsCertificate -ComputerName $computerName -Port $port -TargetHost $computerName

                if ($null -eq $rawCert) {
                    Stop-Function -Message "No certificate returned from $sqlInstanceName" -Target $instance -Continue
                    continue
                }

                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($rawCert)

                # Extract DNS names from Subject Alternative Names
                $dnsNames = @()
                foreach ($extension in $cert.Extensions) {
                    if ($extension.Oid.FriendlyName -eq "Subject Alternative Name") {
                        $asnData = New-Object System.Security.Cryptography.AsnEncodedData($extension.Oid, $extension.RawData)
                        $sanText = $asnData.Format($false)
                        $dnsEntries = $sanText -split ", " | Where-Object { $PSItem -match "^DNS Name=" }
                        $dnsNames = $dnsEntries | ForEach-Object { $PSItem -replace "^DNS Name=", "" }
                        break
                    }
                }

                [PSCustomObject]@{
                    ComputerName = $computerName
                    InstanceName = $instanceName
                    SqlInstance  = $sqlInstanceName
                    Port         = $port
                    Subject      = $cert.Subject
                    Issuer       = $cert.Issuer
                    Thumbprint   = $cert.Thumbprint
                    NotBefore    = $cert.NotBefore
                    Expires      = $cert.NotAfter
                    DnsNameList  = $dnsNames
                    SerialNumber = $cert.SerialNumber
                    Certificate  = $cert
                }
            } catch {
                Stop-Function -Message "Failed to retrieve certificate from $sqlInstanceName | $($PSItem.Exception.Message)" -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}
