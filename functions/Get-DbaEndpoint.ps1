function Get-DbaEndpoint {
    <#
    .SYNOPSIS
        Returns endpoint objects from a SQL Server instance.

    .DESCRIPTION
        Returns endpoint objects from a SQL Server instance.

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
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Not sure why minimumversion isnt working
            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "SQL Server version 9 required - $instance not supported." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $endpoints = $server.Endpoints

            if ($endpoint) {
                $endpoints = $endpoints | Where-Object Name -in $endpoint
            }
            if ($Type) {
                $endpoints = $endpoints | Where-Object EndpointType -in $Type
            }

            foreach ($end in $endpoints) {
                Write-Message -Level Verbose -Message "Getting endpoint $($end.Name) on $($server.Name)"
                if ($end.Protocol.Tcp.ListenerPort) {
                    if ($instance.ComputerName -match '\.') {
                        $dns = $instance.ComputerName
                    } else {
                        try {
                            $dns = [System.Net.Dns]::GetHostEntry($instance.ComputerName).HostName
                        } catch {
                            try {
                                $dns = [System.Net.Dns]::GetHostAddresses($instance.ComputerName)
                            } catch {
                                $dns = $instance.ComputerName
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
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name Port -Value $end.Protocol.Tcp.ListenerPort
                if ($end.Protocol.Tcp.ListenerPort) {
                    Select-DefaultView -InputObject $end -Property ComputerName, InstanceName, SqlInstance, ID, Name, Port, EndpointState, EndpointType, Owner, IsAdminEndpoint, Fqdn, IsSystemObject
                } else {
                    Select-DefaultView -InputObject $end -Property ComputerName, InstanceName, SqlInstance, ID, Name, EndpointState, EndpointType, Owner, IsAdminEndpoint, Fqdn, IsSystemObject
                }
            }
        }
    }
}