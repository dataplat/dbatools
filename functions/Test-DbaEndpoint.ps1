#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Test-DbaEndpoint {
    <#
        .SYNOPSIS
            Tests connectivity for TCP enabled endpoints.

        .DESCRIPTION
            Tests connectivity for TCP enabled endpoints.
    
            Note that if an endpoint does not have a tcp listener port, it will be skipped.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Endpoint
            Return only specific endpoint or endpoints
    
        .PARAMETER InputObject
            Allows piping from Get-DbaEndpoint
    
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Endpoint
            Author: Chrissy LeMaire (@cl), netnerds.net
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Test-DbaEndpoint

        .EXAMPLE
            Test-DbaEndpoint -SqlInstance localhost

            Tests all endpoints on the local default SQL Server instance.
    
            Note that if an endpoint does not have a tcp listener port, it will be skipped.
    
        .EXAMPLE
            Get-DbaEndpoint -SqlInstance localhost, sql2016 -Endpoint Mirror | Test-DbaEndpoint

            Tests all endpoints named Mirroring on sql2016 and localhost.
    
            Note that if an endpoint does not have a tcp listener port, it will be skipped.
 
            .EXAMPLE
            Test-DbaEndpoint -SqlInstance localhost, sql2016 -Endpoint Mirror

            Tests all endpoints named Mirroring on sql2016 and localhost.
    
            Note that if an endpoint does not have a tcp listener port, it will be skipped.
    
            .EXAMPLE
            Test-DbaEndpoint -SqlInstance localhost -Verbose

            Tests all endpoints on the local default SQL Server instance.
    
            See all endpoints that were skipped due to not having a tcp listener port.
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Endpoint,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Endpoint[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaEndpoint -SqlInstance $instance -SqlCredential $SqlCredential #-Endpoint $Endpoint
        }
        
        foreach ($end in $InputObject) {
            if (-not $end.Protocol.Tcp.ListenerPort) {
                Write-Message -Level Verbose -Message "$end on $($end.Parent) does not have a tcp listener port"
            }
            else {
                Write-Message "Connecting to port $($end.Protocol.Tcp.ListenerPort) on $($end.ComputerName) for endpoint $($end.Name)"
                
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    $tcp.Connect($end.ComputerName, $end.Protocol.Tcp.ListenerPort)
                    $tcp.Close()
                    $tcp.Dispose()
                    $connect = "Success"
                }
                catch {
                    $connect = $_
                }
                
                try {
                    $ssl = $end.Protocol.Tcp.SslPort
                    if ($ssl) {
                        $tcp = New-Object System.Net.Sockets.TcpClient
                        $tcp.Connect($end.ComputerName, $ssl)
                        $tcp.Close()
                        $tcp.Dispose()
                        $sslconnect = "Success"
                    }
                    else {
                        $sslconnect = "None"
                    }
                }
                catch {
                    $sslconnect = $_
                }
                
                [pscustomobject]@{
                    ComputerName = $end.ComputerName
                    InstanceName = $end.InstanceName
                    SqlInstance  = $end.SqlInstance
                    Endpoint     = $end.Name
                    Port         = $end.Protocol.Tcp.ListenerPort
                    Connection   = $connect
                    SslConnection = $sslconnect
                }
            }
        }
    }
}