function Get-DbaEndpoint {
    <#
    .SYNOPSIS
        Retrieves SQL Server endpoints with network connectivity details for troubleshooting and documentation.

    .DESCRIPTION
        Retrieves all SQL Server endpoints including DatabaseMirroring, ServiceBroker, Soap, and TSql types with their network configuration details. This function provides essential information for troubleshooting connectivity issues, documenting high availability setups, and performing security audits. It automatically resolves DNS names and constructs connection strings (FQDN format) for endpoints that have TCP listeners, making it easier to validate network accessibility and plan firewall configurations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Endpoint
        Specifies one or more endpoint names to retrieve instead of returning all endpoints. Accepts exact endpoint names and supports multiple values.
        Use this when you need to examine specific endpoints like 'Mirroring' or 'AlwaysOn_health' rather than scanning all configured endpoints.

    .PARAMETER Type
        Filters endpoints by their functional type. Valid options: DatabaseMirroring, ServiceBroker, Soap, and TSql.
        Use this to focus on specific endpoint categories, such as 'DatabaseMirroring' for Always On AG troubleshooting or 'ServiceBroker' for message queuing configurations.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Endpoint
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaEndpoint

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Endpoint

        Returns one Endpoint object per endpoint found on the SQL Server instance, with custom properties added for connection details and network information.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name (service name)
        - SqlInstance: The fully qualified SQL Server instance name (Computer\Instance)
        - ID: The unique identifier of the endpoint
        - Name: The name of the endpoint
        - IPAddress: The IP address the endpoint listens on (when TCP is configured; otherwise null)
        - Port: The TCP port the endpoint listens on (when TCP is configured; otherwise null)
        - EndpointState: The current state of the endpoint (Started or Stopped)
        - EndpointType: The type of endpoint (DatabaseMirroring, ServiceBroker, Soap, or TSql)
        - Owner: The SQL Server login that owns the endpoint
        - IsAdminEndpoint: Boolean indicating if this is an administrative endpoint
        - Fqdn: Fully qualified domain name and port in connection string format (TCP://hostname:port) for endpoints with TCP listeners; null for endpoints without TCP configuration
        - IsSystemObject: Boolean indicating if this is a system-created endpoint

        Additional properties available (from SMO Endpoint object):
        - CreateDate: The date and time when the endpoint was created
        - DateLastModified: The date and time when the endpoint was last modified
        - Payload: Protocol-specific configuration details for the endpoint
        - Protocol: Protocol configuration details (includes Tcp, NamedPipes, SharedMemory configuration objects)
        - ProtocolName: The name of the protocol used

        Note: The IPAddress, Port, and Fqdn properties are custom-added by this function to enhance output. When an endpoint has TCP listeners configured, these properties are populated; otherwise, they are null or empty. The Fqdn property is automatically resolved with DNS lookups to provide a fully qualified domain name for connectivity testing.

    .EXAMPLE
        PS C:\> Get-DbaEndpoint -SqlInstance localhost

        Returns all endpoints on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaEndpoint -SqlInstance localhost, sql2016

        Returns all endpoints for the local and sql2016 SQL Server instances
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Endpoint,
        [ValidateSet('DatabaseMirroring', 'ServiceBroker', 'Soap', 'TSql')]
        [string[]]$Type,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $endpoints = $server.Endpoints

            if ($Endpoint) {
                $endpoints = $endpoints | Where-Object Name -In $Endpoint
            }
            if ($Type) {
                $endpoints = $endpoints | Where-Object EndpointType -In $Type
            }

            foreach ($end in $endpoints) {
                Write-Message -Level Verbose -Message "Getting endpoint $($end.Name) on $($server.Name)"
                if ($end.Protocol.Tcp.ListenerPort) {
                    if ($end.Protocol.Tcp.ListenerIPAddress -ne [System.Net.IPAddress]'0.0.0.0') {
                        $dns = $end.Protocol.Tcp.ListenerIPAddress
                    } elseif ($server.HostPlatform -eq "Linux" -and $server.NetName) {
                        $dns = $server.NetName
                    } elseif ($server.ComputerName -match '\.') {
                        $dns = $server.ComputerName
                    } else {
                        try {
                            $dns = [System.Net.Dns]::GetHostEntry($server.ComputerName).HostName
                        } catch {
                            try {
                                $dns = [System.Net.Dns]::GetHostAddresses($server.ComputerName)
                            } catch {
                                $dns = $server.ComputerName
                            }
                        }
                    }

                    $fqdn = "TCP://" + $dns + ":" + $end.Protocol.Tcp.ListenerPort
                } else {
                    $fqdn = $null
                }

                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name Fqdn -Value $fqdn
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name IPAddress -Value $end.Protocol.Tcp.ListenerIPAddress
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name Port -Value $end.Protocol.Tcp.ListenerPort
                if ($end.Protocol.Tcp.ListenerPort) {
                    Select-DefaultView -InputObject $end -Property ComputerName, InstanceName, SqlInstance, ID, Name, IPAddress, Port, EndpointState, EndpointType, Owner, IsAdminEndpoint, Fqdn, IsSystemObject
                } else {
                    Select-DefaultView -InputObject $end -Property ComputerName, InstanceName, SqlInstance, ID, Name, EndpointState, EndpointType, Owner, IsAdminEndpoint, Fqdn, IsSystemObject
                }
            }
        }
    }
}