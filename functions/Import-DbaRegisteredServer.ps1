#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Import-DbaRegisteredServer {
    <#
        .SYNOPSIS
            Imports stuff

        .DESCRIPTION
            Imports stuff

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Group
            Specifies one or more groups to include from SQL Server Central Management Server.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Chrissy LeMaire (@cl)
            Tags: RegisteredServer, CMS

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Import-DbaRegisteredServer

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a

            Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials.

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a -IncludeSelf

            Gets a list of servers from the CMS on sqlserver2014a and includes sqlserver2014a in the output results.

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a -SqlCredential $credential | Select-Object -Unique -ExpandProperty ServerName

            Returns only the server names from the CMS on sqlserver2014a, using SQL Authentication to authenticate to the server.

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR, Accounting

            Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

        .EXAMPLE
            Import-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR\Development

            Returns a list of servers in the HR and sub-group Development from the CMS on sqlserver2014a.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    
    begin {        
        process {
            foreach ($instance in $SqlInstance) {
                try {
                    Write-Message -Level Verbose -Message "Connecting to $instance"
                    $server = Get-DbaRegisteredServersStore -SqlInstance $instance -SqlCredential $sqlcredential
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                
                foreach ($object in $InputObject) {
                    if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                        $parentserver = Get-RegServerParent -InputObject $reggroup
                        
                        if ($null -eq $parentserver) {
                            Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
                        }
                        
                        $server = $parentserver.ServerConnection
                        
                        Add-DbaRegisteredServer -SqlInstance $server -Name $object.Name -ServerName $object.ServerName -Description $object.Description
                    }
                    elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                        Add-DbaRegisteredServerGroup
                    }
                    else {
                        
                    }
                }
            }
        }
    }
}