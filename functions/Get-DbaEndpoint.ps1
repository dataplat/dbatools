#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaEndpoint {
<#
    .SYNOPSIS
        Gets SQL Endpoint(s) information for each instance(s) of SQL Server.
        
    .DESCRIPTION
        The Get-DbaEndpoint command gets SQL Endpoint(s) information for each instance(s) of SQL Server.
        
    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.
        
    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
        
    .PARAMETER EndPoint
        Return only specific endpoint or endpoints
        
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
        
    .NOTES
        Tags: Endpoint
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com
        
        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
        
    .LINK
        https://dbatools.io/Get-DbaEndpoint
        
    .EXAMPLE
        Get-DbaEndpoint -SqlInstance localhost
        
        Returns all Endpoint(s) on the local default SQL Server instance
        
    .EXAMPLE
        Get-DbaEndpoint -SqlInstance localhost, sql2016
        
        Returns all Endpoint(s) for the local and sql2016 SQL Server instances
        
#>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Endpoint,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            # Not sure why minimumversion isnt working
            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "SQL Server version 9 required - $instance not supported." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            $endpoints = $server.Endpoints
            
            if (Test-Bound -ParameterName EndPoint) {
                $endpoints = $endpoints | Where-Object Name -in $endpoint
            }
            
            foreach ($end in $endpoints) {
                if ($end.Protocol.Tcp.ListenerPort) {
                    if ($instance.ComputerName -match '\.') {
                        $dns = $instance.ComputerName
                    }
                    else {
                        $dns = [System.Net.Dns]::GetHostEntry($instance.ComputerName).HostName
                    }
                                        
                    $fqdn = "TCP://" + $dns + ":" + $end.Protocol.Tcp.ListenerPort
                }
                else {
                    $fqdn = $null
                }
                
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $end -MemberType NoteProperty -Name Fqdn -Value $fqdn
                
                Select-DefaultView -InputObject $end -Property ComputerName, InstanceName, SqlInstance, ID, Name, EndpointState, EndpointType, Owner, IsAdminEndpoint, Fqdn, IsSystemObject
            }
        }
    }
}