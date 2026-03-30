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

    }

    process {
        foreach ($instance in $SqlInstance) {

            try {


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
                Stop-Function -Message "Failed to retrieve certificate from $instance" -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}