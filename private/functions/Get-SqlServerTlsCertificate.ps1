# Source: https://gist.github.com/jborean93/44f92e4dfa613c5a1e7889fa7a7c2563

# Copyright: (c) 2023, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

Function Get-SqlServerTlsCertificate {
    <#
    .SYNOPSIS
    Gets the MS SQL X509 Certificate.

    .DESCRIPTION
    Gets the X509 Certificate that is being used by a remote MS SQL Server.
    This certificate contains information like the Subject, SAN entries, expiry and other useful information for debugging purposes.

    .PARAMETER ComputerName
    The remote MS SQL Server to extract the certificate from.

    .PARAMETER ConnectTimeout
    The timeout, in milliseconds, to wait until the connection was successful, defaults to 5000 (5 seconds).
    If the timeout is reached, the cmdlet will write an error.

    .PARAMETER ConnectionType
    The connection type to use for retrieving the certificate, defaults to SQLBrowser.
    This can be set to SQLBrowser, NamedPipe, or TCP.
    The SQLBrowser option will use the SQL Browser service to find the named pipe or TCP port for the instance requested.
    The SQLBrowser needs access to the UDP port 1434 as well as the NamedPipe or TCP Port that is selected to work.
    The NamedPipe option will connect to the named pipe for the instance requested.
    The NamedPipe will need access to the TCP port 445 to work.
    The TCP option will connect to the TCP port requested.

    .PARAMETER InstanceName
    The MS SQL instance to connect to.
    When used with '-ConnectionType SQLBrowser', it will only connect to the instance that matches this name.
    When used with '-ConnectionType NamedPipe', it will use this instance name to build the named pipe name.
    Set to an empty string to use the first instance found by the SQLBrowser.

    .PARAMETER Port
    The TCP port to use for the connection, defaults to 1433.
    This is only used if '-ConnectionType TCP' is requested.

    .PARAMETER StrictEncrypt
    Perform strict encryption that was introduced with TDS 8.0 (SQL Server 2022 and newer).
    Strict encryption simplifies the connection process but will only work if the server is new enough to support it.

    .EXAMPLE
    PS> Get-SqlServerTlsCertificate -ComputerName sql01
    Gets the certificate of the first instance found on sql01 using the SQL Browser service to find the TCP port or Named Pipe.

    .EXAMPLE
    PS> Get-SqlServerTlsCertificate -ComputerName sql01 -Instance MySQLInstance
    Gets the certificate for the instance 'sql01\MySQLInstance' using the SQL Browser service to find the TCP port or Named Pipe.

    .EXAMPLE
    PS> Get-SqlServerTlSCertificate -ComputerName sql01 -Port 65334 -ConnectionType TCP
    Gets the certificate for server sql01 using the TCP port 65334

    .EXAMPLE
    PS> Get-SqlServerTlsCertificate -ComputerName sql01 -ConnectionType NamedPipe
    Gets the certificate for the default instance on sql01 using the Named Pipe connection.

    .EXAMPLE
    PS> Get-SqlServerTlsCertificate -ComputerName sql01 -InstanceName MySQLInstance -ConnectionType NamedPipe
    Gets the certificate for the instance 'sql01\MySQLInstance' using the Named Pipe connection.

    .EXAMPLE
    PS> $cert = Get-SqlServerTlsCertificate -ComputerName sql01
    PS> $certBytes = $cert.Export("Cert")
    PS> $setParams = @{}
    PS> if ($PSVersionTable.PSVersion -lt [Version]'6.0') {
    ...     $setParams.Raw = $true
    ... } else {
    ...     $setParams.AsByteStream = $true
    ... }
    PS> Set-Content -Path sql01.crt -Value $certBytes @setParams
    Gets the certificate for the SQL server sql01 and exports it to a .crt file for use in Windows.

    .OUTPUTS
    System.Security.Cryptography.X509Certificates.X509Certificate2
    This cmdlet will output the X509Certificate2 object retrieved from the server.

    .NOTES
    Run with -Verbose to get a better understanding of how this cmdlet connects to the MS SQL server.
    A warning will be emitted if the remote certificate is not trusted and it will try to include the reasons why.
    #>
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        [Parameter(Mandatory)]
        [string]
        $ComputerName,

        [Parameter()]
        [int]
        $ConnectTimeout = 5000,

        [Parameter()]
        [ValidateSet("SQLBrowser", "TCP", "NamedPipe")]
        [string]
        $ConnectionType = "SQLBrowser",

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $InstanceName = "",

        [Parameter()]
        [int]
        $Port = 1433,

        [Parameter()]
        [switch]
        $StrictEncrypt
    )

    if (-not ([System.Management.Automation.PSTypeName]"TdsTlsStream").Type) {
        Add-Type -TypeDefinition @"
using System;
using System.IO;

public class TdsTlsStream : Stream {
    private Stream _innerStream;
    private int _payloadLength = 0;

    public TdsTlsStream(Stream innerStream) {
        _innerStream = innerStream;
    }

    public override bool CanRead { get { return _innerStream.CanRead; } }
    public override bool CanWrite { get { return _innerStream.CanWrite; } }
    public override bool CanSeek { get { return _innerStream.CanSeek; } }
    public override long Length { get { return _innerStream.Length; } }
    public override long Position {
        get { return _innerStream.Position; }
        set { _innerStream.Position = value; }
    }
    public override int ReadTimeout { get { return _innerStream.ReadTimeout; } }
    public override int WriteTimeout { get { return _innerStream.WriteTimeout; } }

    public override void Flush() { _innerStream.Flush(); }
    public override long Seek(long offset, SeekOrigin origin) { return _innerStream.Seek(offset, origin); }
    public override void SetLength(long value) { _innerStream.SetLength(value); }

    public override int Read(byte[] buffer, int offset, int count) {
        // We need to strip off the TDS header before setting the Buffer
        if (_payloadLength == 0) {
            byte[] header = new byte[8];
            int read = 0;
            while (read < 8) {
                read += _innerStream.Read(header, 0, 8);
            }

            int lengthBeforeHeader = (int)BitConverter.ToUInt16(new byte[] { header[3], header[2] }, 0);
            lengthBeforeHeader -= 8;
            _payloadLength = lengthBeforeHeader;
        }

        if (count > _payloadLength) {
            count = _payloadLength;
        }
        int bytesRead = _innerStream.Read(buffer, offset, count);
        _payloadLength -= bytesRead;
        return bytesRead;
    }

    public override void Write(byte[] buffer, int offset, int count) {
        byte[] newPayload = GenerateTdsHeader(buffer, offset, count);
        _innerStream.Write(newPayload, 0, newPayload.Length);
    }

    private byte[] GenerateTdsHeader(byte[] payload, int offset, int count) {
        // The length is big endian encoded so it is inserted in reverse order
        byte[] lengthBytes = BitConverter.GetBytes((ushort)(count + 8));

        byte[] newPayload = new byte[8 + count];
        newPayload[0] = 0x12;  // Type - Pre-Login
        newPayload[1] = 0x01;  // Status - End of message (EOM)
        newPayload[2] = lengthBytes[1];
        newPayload[3] = lengthBytes[0];
        newPayload[4] = 0;  // SPID
        newPayload[5] = 0;  // SPID
        newPayload[6] = 0;  // PacketID
        newPayload[7] = 0;  // Window
        Array.Copy(payload, offset, newPayload, 8, count);

        return newPayload;
    }
}
"@
    }

    $udpClient = $socket = $targetStream = $sslStream = $null
    try {
        $pipeName = if ($InstanceName -and $InstanceName -ne 'MSSQLSERVER') {
            'MSSQL${0}\sql\query' -f $InstanceName
        }
        else {
            'sql\query'
        }

        if ($ConnectionType -eq "SQLBrowser") {
            # Use the SQLBrowser
            # https://learn.microsoft.com/en-us/openspecs/windows_protocols/mc-sqlr/2e1560c9-5097-4023-9f5e-72b9ff1ec3b1
            $udpClient = New-Object -TypeName System.Net.Sockets.UdpClient -ArgumentList @($ComputerName, 1434)
            $udpClient.Client.SendTimeout = $ConnectTimeout
            $udpClient.Client.ReceiveTimeout = $ConnectTimeout
            $null = $udpClient.Send([byte[]]@(0x03), 1)  # CLNT_UCAST_EX
            $resp = $udpClient.Receive([ref]$null)

            $respSize = [System.BitConverter]::ToUInt16($resp, 1)
            $rawResponse = [System.Text.Encoding]::UTF8.GetString($resp, 3, $respSize)
            Write-Verbose -Message "Recieved SQL Browser response: '$rawResponse'"
            $response = $rawResponse -split ';'

            $instanceInfo = [Ordered]@{}
            $remoteInstance = @(
                for ($i = 0; $i -lt $response.Length; $i += 2) {
                    if ($response[$i]) {
                        $instanceInfo[$response[$i]] = $response[$i + 1]
                    }
                    elseif ($i -eq $response.Length - 1) {
                        break
                    }
                    else {
                        $info = [PSCustomObject]$instanceInfo
                        Write-Verbose -Message "Processed SQL Browser Response:`n$($info | Out-String)"

                        $info
                        $instanceInfo = [Ordered]@{}
                        $i -= 1
                    }
                }
            ) | Where-Object { -not $InstanceName -or $_.InstanceName -eq $InstanceName } | Select-Object -First 1

            if ($remoteInstance.np) {
                $ConnectionType = 'NamedPipe'
                $ComputerName = $remoteInstance.ServerName
                $pipeName = $remoteInstance.np -replace "\\\\.*?\\pipe\\(.*)", '$1'
            }
            elseif ($remoteInstance.tcp) {
                $ConnectionType = 'TCP'
                $ComputerName = $remoteInstance.ServerName
                $Port = $remoteInstance.tcp
            }
            else {
                throw "Failed to receive any SQL Browser responses from $($ComputerName):1434, cannot continue"
            }
        }

        if ($ConnectionType -eq "TCP") {
            Write-Verbose -Message "Connecting to TCP/IP endpoint $($ComputerName):$Port"

            $socket = New-Object -TypeName System.Net.Sockets.TcpClient
            $connectTask = $socket.ConnectAsync($ComputerName, $Port)
            if (-not $connectTask.Wait($ConnectTimeout)) {
                throw "Timed out connecting to TCP/IP endpoint $($ComputerName):$Port"
            }

            $targetStream = $socket.GetStream()
        }
        else {
            Write-Verbose -Message "Connecting to Named Pipe endpoint \\$($ComputerName)\pipe\$pipeName"
            $targetStream = New-Object -TypeName System.IO.Pipes.NamedPipeClientStream -ArgumentList @(
                $ComputerName,
                $pipeName,
                [System.IO.Pipes.PipeDirection]::InOut)
            $targetStream.Connect($ConnectTimeout)
        }

        # Before TDS 8.0, TLS was done after the Pre-Login message after it was
        # negotiated with the server. It also needs to prepend a header to each TLS
        # payload making it more difficult. TDS 8.0 (Encrypt=strict) is a lot
        # simpler as the TLS handshake is done before anything.
        if ($StrictEncrypt) {
            Write-Verbose -Message "Using TDS 8 TLS Handshake"
            $streamToWrap = $targetStream
        }
        else {
            Write-Verbose -Message "Using TDS 7.x Pre-Login method for the TLS handshake"

            # This is a pre-calculated TDS Pre-Login payload with the ENCRYPTION
            # value of ENCRYPT_REQ (0x03).
            # https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-tds/60f56408-0188-4cd5-8b90-25c6f2423868
            $tdsPreLogin = [byte[]]@(
                0x12, 0x01, 0x00, 0x2f, 0x00, 0x00, 0x01, 0x00,
                0x00, 0x00, 0x1a, 0x00, 0x06, 0x01, 0x00, 0x20,
                0x00, 0x01, 0x02, 0x00, 0x21, 0x00, 0x01, 0x03,
                0x00, 0x22, 0x00, 0x04, 0x04, 0x00, 0x26, 0x00,
                0x01, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
            )
            $targetStream.Write($tdsPreLogin, 0, $tdsPreLogin.Count)

            $headerBytes = New-Object byte[] 8
            $read = 0
            while ($read -ne $headerBytes.Length) {
                $read += $targetStream.Read($headerBytes, $read, $headerBytes.Length - $read)
            }

            # Integer values are big endian encoded so swap them around. It also
            # includes the header length which we've already gotten
            $payloadLength = [System.BitConverter]::ToUInt16([byte[]]@($headerBytes[3], $headerBytes[2]), 0)
            $payloadLength -= 8

            $tdsPreLoginResp = New-Object byte[] $payloadLength
            $read = 0
            while ($read -ne $tdsPreLoginResp.Length) {
                $read += $targetStream.Read($tdsPreLoginResp, $read, $tdsPreLoginResp.Length - $read)
            }

            # The TDS Pre-Login payload starts with a variable amount of headers
            #	TYPE - BYTE
            #	OFFSET - USHORT (offset in the payload of the value)
            #	LENGTH - USHORT
            # The headers are terminated with the type 0xFF. We want to extract the
            # value for the ENCRYPT type (1) from the payload to see if the server
            # supported encryption.
            $serverEncrypt = 0
            $offset = 0
            while ($true) {
                $plOptionType = $tdsPreLoginResp[$offset]
                if ($plOptionType -eq 0xFF) {
                    break
                }
                elseif ($plOptionType -ne 1) {
                    $offset += 5
                    continue
                }

                $valueOffset = [System.BitConverter]::ToUInt16([byte[]]@($tdsPreLoginResp[$offset + 2], $tdsPreLoginResp[$offset + 1]), 0)
                $serverEncrypt = $tdsPreLoginResp[$valueOffset]
                break
            }

            # Strip off the extra flags, we only care about these specific bits
            $serverEncrypt = $serverEncrypt -band 0x0F

            # ENCRYPT_OFF, ENCRYPT_NOT_SUP
            if ($serverEncrypt -in @(0, 2)) {
                $msg = 'Server reported an encryption level of 0x{0:X2} which indicates it does not support TDS encryption.' -f $serverEncrypt
                throw $msg
            }

            # Now we know the server supports TLS we need to wrap the raw stream
            # with a custom wrapper to ensure each TLS payload sent below is
            # preceeded with the TDS header as required. While not implemented
            # there is a note that TDS 7.1 or earlier (SQL Server 2000 or earlier)
            # should use the table response type (0x04) instead. As this is so old
            # I'm not going to implement that.
            $streamToWrap = New-Object -TypeName TdsTlsStream -ArgumentList $targetStream
        }

        # Create the SslStream with a disable certificate verification callback.
        # This allows it to connect to a self signed or cert with different
        # hostname. The callback will also capture more information about the peer
        # Allows us to emit warnings if it was going to fail.
        $certState = @{}
        $sslValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback] {
            param($Sender, $Certificate, $Chain, $SslPolicyErrors)

            $certState.Chain = $Chain
            $certState.SslPolicyErrors = $SslPolicyErrors
            $true
        }
        $sslStream = New-Object -TypeName System.Net.Security.SslStream -ArgumentList @($streamToWrap, $false, $sslValidationCallback)
        Write-Verbose -Message "Starting TLS Handshake"
        $sslStream.AuthenticateAsClient($ComputerName)
        Write-Verbose -Message "TLS result: $($certState.SslPolicyErrors)"

        if ($certState.SslPolicyErrors -ne 'None') {
            $msg = @(
                "Client does not trust remote certificate: $($certState.SslPolicyErrors)"
                $certState.ChainStatus | ForEach-Object { $_.Status; $_.StatusInformation }
            ) -join ([System.Environment]::NewLine)
            Write-Warning -Message $msg.TrimEnd()
        }

        $cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $sslStream.RemoteCertificate
        Write-Verbose -Message "Found cert for $($cert.Subject), Expires: $($cert.NotAfter), SANs: $($cert.DnsNameList -join ", ")"

        $cert
    }
    catch {
        $PSCmdlet.WriteError($_)
    }
    finally {
        if ($udpClient) { $udpClient.Dispose() }
        if ($sslStream) { $sslStream.Dispose() }
        if ($targetStream) { $targetStream.Dispose() }
        if ($socket) { $socket.Dispose() }
    }
}
