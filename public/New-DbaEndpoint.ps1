function New-DbaEndpoint {
    <#
    .SYNOPSIS
        Creates SQL Server endpoints for database mirroring, Service Broker, SOAP, or T-SQL communication.

    .DESCRIPTION
        Creates SQL Server endpoints that enable communication between instances for high availability features like availability groups and database mirroring. Database mirroring endpoints are the most common type, required for setting up availability groups and database mirroring partnerships. The function also supports Service Broker endpoints for message queuing, SOAP endpoints for web services, and T-SQL endpoints for remote connections. Automatically generates TCP ports if not specified and handles encryption settings to ensure secure communication between SQL Server instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies the name for the new endpoint. Defaults to hadr_endpoint for DatabaseMirroring endpoints.
        Required when creating ServiceBroker, Soap, or TSql endpoints as these need unique names for identification.

    .PARAMETER Type
        Defines the endpoint type to create. DatabaseMirroring endpoints enable availability groups and database mirroring.
        ServiceBroker enables message queuing, Soap creates web service endpoints, and TSql allows remote connections. Defaults to DatabaseMirroring.

    .PARAMETER Protocol
        Sets the communication protocol for the endpoint. TCP is standard for database mirroring and availability groups.
        Use Http for SOAP endpoints, NamedPipes for local connections, or SharedMemory for same-machine communication. Defaults to Tcp.

    .PARAMETER Role
        Determines the database mirroring role this endpoint can serve. All allows the instance to act as principal, mirror, or witness.
        Partner restricts to principal/mirror roles only, Witness allows witness-only, None disables mirroring roles. Defaults to All.

    .PARAMETER IPAddress
        Sets which IP address the endpoint listens on for incoming connections. Use 0.0.0.0 to listen on all available interfaces.
        Specify a particular IP address to restrict connections to that interface only, useful for multi-homed servers. Defaults to 0.0.0.0 (all interfaces).

    .PARAMETER Port
        Specifies the TCP port number for the endpoint to listen on. Auto-generates a port starting from 5022 if not specified.
        Use this when you need a specific port for firewall rules or standardization across instances.

    .PARAMETER SslPort
        Sets the SSL port number for HTTPS endpoints when using HTTP protocol. Only applicable for Soap endpoints using HTTPS.
        Required when creating secure web service endpoints that need encrypted communication over HTTP.

    .PARAMETER Certificate
        Name of a database certificate to use for endpoint authentication instead of Windows authentication.
        The certificate must already exist in the master database and provides certificate-based authentication for enhanced security.

    .PARAMETER EndpointEncryption
        Controls whether encryption is enforced for endpoint connections. Required forces all connections to use encryption.
        Supported allows both encrypted and unencrypted connections, Disabled prevents encryption. Defaults to Required for security.

    .PARAMETER EncryptionAlgorithm
        Sets the encryption algorithm used to secure endpoint communications. AES provides the strongest security.
        RC4 options are available for backward compatibility but are less secure. Use None only when encryption is disabled. Defaults to Aes.

    .PARAMETER AuthenticationOrder
        Defines the authentication methods and their priority order for endpoint connections. Negotiate automatically chooses the best available method.
        Use certificate options when requiring certificate-based authentication, or specific methods like Kerberos for domain environments. Defaults to Negotiate.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Owner
        Sets the SQL Server login that owns the endpoint. The owner has full control permissions on the endpoint.
        Defaults to the sa account if available, otherwise uses the current connection's login for ownership.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Endpoint
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaEndpoint

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.EndPoint

        Returns one EndPoint object for each endpoint successfully created. The endpoint object represents the newly created SQL Server endpoint configured with the specified type, protocol, and communication settings.

        Default display properties (via Select-DefaultView from Get-DbaEndpoint, when TCP port is configured):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ID: The endpoint identifier
        - Name: The name of the endpoint (e.g., hadr_endpoint for DatabaseMirroring)
        - IPAddress: The IP address the endpoint listens on
        - Port: The TCP port number the endpoint listens on
        - EndpointState: The current state of the endpoint (Started, Stopped, Disabled)
        - EndpointType: The endpoint type (DatabaseMirroring, ServiceBroker, Soap, TSql)
        - Owner: The SQL Server login that owns the endpoint
        - IsAdminEndpoint: Boolean indicating if the endpoint is restricted to administrators only
        - Fqdn: The fully qualified domain name with TCP protocol and port
        - IsSystemObject: Boolean indicating if this is a system endpoint

        When no TCP port is configured, IPAddress and Port are excluded from default display.

        Additional properties available (from SMO EndPoint object):
        - ProtocolType: The protocol type enumeration value
        - Parent: Reference to the parent Server object
        - Urn: The Uniform Resource Name for the endpoint
        - Protocol: The Protocol object containing TCP, HTTP, Named Pipes configuration details
        - Payload: The Payload object containing endpoint-specific configuration (DatabaseMirroring, ServiceBroker, Soap, TSql)

    .EXAMPLE
        PS C:\> New-DbaEndpoint -SqlInstance localhost\sql2017 -Type DatabaseMirroring

        Creates a database mirroring endpoint on localhost\sql2017 which using the default port

    .EXAMPLE
        PS C:\> New-DbaEndpoint -SqlInstance localhost\sql2017 -Type DatabaseMirroring -Port 5055

        Creates a database mirroring endpoint on localhost\sql2017 which uses alternative port 5055

    .EXAMPLE
        PS C:\> New-DbaEndpoint -SqlInstance localhost\sql2017 -Type DatabaseMirroring -IPAddress 192.168.0.15 -Port 5055

        Creates a database mirroring endpoint on localhost\sql2017 which binds only on ipaddress 192.168.0.15 and port 5055
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Endpoint")]
        [string]$Name,
        [ValidateSet('DatabaseMirroring', 'ServiceBroker', 'Soap', 'TSql')]
        [string]$Type = 'DatabaseMirroring',
        [ValidateSet('Tcp', 'NamedPipes', 'Http', 'Via', 'SharedMemory')]
        [string]$Protocol = 'Tcp',
        [ValidateSet('All', 'None', 'Partner', 'Witness')]
        [string]$Role = 'All',
        [ValidateSet('Disabled', 'Required', 'Supported')]
        [string]$EndpointEncryption = 'Required',
        [ValidateSet('Aes', 'AesRC4', 'None', 'RC4', 'RC4Aes')]
        [string]$EncryptionAlgorithm = 'Aes',
        [ValidateSet('Certificate', 'CertificateKerberos', 'CertificateNegotiate', 'CertificateNtlm', 'Kerberos', 'KerberosCertificate', 'Negotiate', 'NegotiateCertificate', 'Ntlm', 'NtlmCertificate')]
        [string]$AuthenticationOrder, # defaults to Negotiate anyway
        [string]$Certificate,
        [System.Net.IPAddress]$IPAddress = '0.0.0.0',
        [int]$Port,
        [int]$SslPort,
        [string]$Owner,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName Name -Not)) {
            if ($Type -eq 'DatabaseMirroring') {
                $Name = 'hadr_endpoint'
            } else {
                Stop-Function -Message "Name is required when Type is not DatabaseMirroring"
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not (Test-Bound -ParameterName Owner)) {
                $Owner = Get-SaLoginName -SqlInstance $server
            }

            if ($Certificate) {
                $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
                if (-not $cert) {
                    Stop-Function -Message "Certificate $Certificate does not exist on $instance" -Target $Certificate -Continue
                }
            }

            # Thanks to https://github.com/mmessano/PowerShell/blob/master/SQL-ConfigureDatabaseMirroring.ps1
            if ($Port) {
                $tcpPort = $port
            } else {
                $thisport = (Get-DbaEndpoint -SqlInstance $server).Protocol.Tcp
                $measure = $thisport | Measure-Object ListenerPort -Maximum

                if ($thisport.ListenerPort -eq 0) {
                    $tcpPort = 5022
                } elseif ($measure.Maximum) {
                    $maxPort = $measure.Maximum
                    #choose a random port that is greater than the current max port
                    $tcpPort = $maxPort + (New-Object Random).Next(1, 500)
                } else {
                    $maxPort = 5000
                    #choose a random port that is greater than the current max port
                    $tcpPort = $maxPort + (New-Object Random).Next(1, 500)
                }
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Creating endpoint $Name of type $Type using protocol $Protocol and if TCP then using IPAddress $IPAddress and Port $tcpPort")) {
                try {
                    $endpoint = New-Object Microsoft.SqlServer.Management.Smo.EndPoint $server, $Name
                    $endpoint.ProtocolType = [Microsoft.SqlServer.Management.Smo.ProtocolType]::$Protocol
                    $endpoint.EndpointType = [Microsoft.SqlServer.Management.Smo.EndpointType]::$Type
                    $endpoint.Owner = $Owner
                    if ($Protocol -eq "TCP") {
                        $endpoint.Protocol.Tcp.ListenerIPAddress = $IPAddress
                        $endpoint.Protocol.Tcp.ListenerPort = $tcpPort
                        $endpoint.Payload.DatabaseMirroring.ServerMirroringRole = [Microsoft.SqlServer.Management.Smo.ServerMirroringRole]::$Role
                        if (Test-Bound -ParameterName SslPort) {
                            $endpoint.Protocol.Http.SslPort = $SslPort
                        }
                        $endpoint.Payload.DatabaseMirroring.EndpointEncryption = [Microsoft.SqlServer.Management.Smo.EndpointEncryption]::$EndpointEncryption
                        $endpoint.Payload.DatabaseMirroring.EndpointEncryptionAlgorithm = [Microsoft.SqlServer.Management.Smo.EndpointEncryptionAlgorithm]::$EncryptionAlgorithm
                        if (Test-Bound -ParameterName AuthenticationOrder) {
                            $endpoint.Payload.DatabaseMirroring.EndpointAuthenticationOrder = [Microsoft.SqlServer.Management.Smo.EndpointAuthenticationOrder]::$AuthenticationOrder
                        }
                    }
                    if ($Certificate) {
                        $outscript = $endpoint.Script()
                        $outscript = $outscript.Replace("ROLE = ALL,", "ROLE = ALL, AUTHENTICATION = CERTIFICATE $cert,")
                        $server.Query($outscript)
                    } else {
                        $null = $endpoint.Create()
                    }

                    $server.Endpoints.Refresh()
                    Get-DbaEndpoint -SqlInstance $server -Endpoint $name
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}