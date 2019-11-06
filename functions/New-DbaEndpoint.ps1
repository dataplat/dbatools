function New-DbaEndpoint {
    <#
    .SYNOPSIS
        Creates endpoints on a SQL Server instance.

    .DESCRIPTION
        Creates endpoints on a SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The name of the endpoint. If a name is not specified, one will be auto-generated.

    .PARAMETER Type
        The type of endpoint. Defaults to DatabaseMirroring. Options: DatabaseMirroring, ServiceBroker, Soap, TSql

    .PARAMETER Protocol
        The type of protocol. Defaults to tcp. Options: Tcp, NamedPipes, Http, Via, SharedMemory

    .PARAMETER Role
        The type of role. Defaults to All. Options: All, None, Partner, Witness

    .PARAMETER Port
        Port for TCP. If one is not provided, it will be auto-generated.

    .PARAMETER SslPort
        Port for SSL

    .PARAMETER Certificate
        Database certificate used for authentication.

    .PARAMETER EndpointEncryption
        Used to specify the state of encryption on the endpoint. Defaults to required.
        Disabled
        Required
        Supported

    .PARAMETER EncryptionAlgorithm
        Specifies an encryption algorithm used on an endpoint. Defaults to Aes.

        Options are:
        AesRC4
        Aes
        None
        RC4
        RC4Aes

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Owner
        Owner of the endpoint. Defaults to sa.

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

    .EXAMPLE
        PS C:\> New-DbaEndpoint -SqlInstance localhost\sql2017 -Type DatabaseMirroring

        Creates a database mirroring endpoint on localhost\sql2017 which using the default port

    .EXAMPLE
        PS C:\> New-DbaEndpoint -SqlInstance localhost\sql2017 -Type DatabaseMirroring -Port 5055

        Creates a database mirroring endpoint on localhost\sql2017 which uses alternative port 5055
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
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
        [string]$Certificate,
        [int]$Port,
        [int]$SslPort,
        [string]$Owner,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName Name -Not)) {
            $name = "endpoint-" + [DateTime]::Now.ToString('s').Replace(":", "-")
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not (Test-Bound -ParameterName Owner)) {
                $Owner = Get-SaLoginName -SqlInstance $server
            }

            if ($Certificate) {
                $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
                if (-not $cert) {
                    Stop-Function -Message "Certificate $Certificate does not exist on $instance" -ErrorRecord $_ -Target $Certificate -Continue
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

            if ($Pscmdlet.ShouldProcess($server.Name, "Creating endpoint $Name of type $Type using protocol $Protocol and if TCP then using Port $tcpPort")) {
                try {
                    $endpoint = New-Object Microsoft.SqlServer.Management.Smo.EndPoint $server, $Name
                    $endpoint.ProtocolType = [Microsoft.SqlServer.Management.Smo.ProtocolType]::$Protocol
                    $endpoint.EndpointType = [Microsoft.SqlServer.Management.Smo.EndpointType]::$Type
                    $endpoint.Owner = $Owner
                    if ($Protocol -eq "TCP") {
                        $endpoint.Protocol.Tcp.ListenerPort = $tcpPort
                        $endpoint.Payload.DatabaseMirroring.ServerMirroringRole = [Microsoft.SqlServer.Management.Smo.ServerMirroringRole]::$Role
                        if (Test-Bound -ParameterName SslPort) {
                            $endpoint.Protocol.Tcp.SslPort = $SslPort
                        }

                        $endpoint.Payload.DatabaseMirroring.EndpointEncryption = [Microsoft.SqlServer.Management.Smo.EndpointEncryption]::$EndpointEncryption
                        $endpoint.Payload.DatabaseMirroring.EndpointEncryptionAlgorithm = [Microsoft.SqlServer.Management.Smo.EndpointEncryptionAlgorithm]::$EncryptionAlgorithm

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