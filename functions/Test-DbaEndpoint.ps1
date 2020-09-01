function Test-DbaEndpoint {
    <#
    .SYNOPSIS
        Performs a simple connectivity test for TCP and SSL enabled endpoints.

    .DESCRIPTION
        Performs a simple connectivity test for TCP and SSL enabled endpoints. Tests if port is accessible, not if endpoint is working.

        Note that if an endpoint does not have a tcp listener port, it will be skipped.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Endpoint
        Test only specific endpoint or endpoints.

    .PARAMETER InputObject
        Enables piping from Get-DbaEndpoint.

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
        https://dbatools.io/Test-DbaEndpoint

    .EXAMPLE
        PS C:\> Test-DbaEndpoint -SqlInstance localhost

        Tests all endpoints on the local default SQL Server instance.

        Note that if an endpoint does not have a tcp listener port, it will be skipped.

    .EXAMPLE
        PS C:\> Get-DbaEndpoint -SqlInstance localhost, sql2016 -Endpoint Mirror | Test-DbaEndpoint

        Tests all endpoints named Mirroring on sql2016 and localhost.

        Note that if an endpoint does not have a tcp listener port, it will be skipped.

    .EXAMPLE
        PS C:\> Test-DbaEndpoint -SqlInstance localhost, sql2016 -Endpoint Mirror

        Tests all endpoints named Mirroring on sql2016 and localhost.

        Note that if an endpoint does not have a tcp listener port, it will be skipped.

    .EXAMPLE
        PS C:\> Test-DbaEndpoint -SqlInstance localhost -Verbose

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
            $InputObject += Get-DbaEndpoint -SqlInstance $instance -SqlCredential $SqlCredential -Endpoint $Endpoint
        }

        foreach ($end in $InputObject) {
            if (-not $end.Protocol.Tcp.ListenerPort) {
                Write-Message -Level Verbose -Message "$end on $($end.Parent) does not have a tcp listener port"
            } else {
                Write-Message "Connecting to port $($end.Protocol.Tcp.ListenerPort) on $($end.ComputerName) for endpoint $($end.Name)"

                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    $tcp.Connect($end.ComputerName, $end.Protocol.Tcp.ListenerPort)
                    $tcp.Close()
                    $tcp.Dispose()
                    $connect = "Success"
                } catch {
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
                    } else {
                        $sslconnect = "None"
                    }
                } catch {
                    $sslconnect = $_
                }

                [pscustomobject]@{
                    ComputerName  = $end.ComputerName
                    InstanceName  = $end.InstanceName
                    SqlInstance   = $end.SqlInstance
                    Endpoint      = $end.Name
                    Port          = $end.Protocol.Tcp.ListenerPort
                    Connection    = $connect
                    SslConnection = $sslconnect
                }
            }
        }
    }
}