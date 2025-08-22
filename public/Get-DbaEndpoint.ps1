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
        Return only specific endpoints.

    .PARAMETER Type
        Return only specific types of endpoints. Options include: DatabaseMirroring, ServiceBroker, Soap, and TSql.

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