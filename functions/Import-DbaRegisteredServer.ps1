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
            Imports to specific group
    
        .PARAMETER InputObject
            Enables piping from Get-DbaRegisteredServer, Get-DbaRegisteredServerGroup, CSVs and other objects.
    
            If importing from CSV or other object, a column named ServerName is required. Optional columns include Name, Description and Group.
    
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
        [string]$Group,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            foreach ($object in $InputObject) {
                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                    Add-DbaRegisteredServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $Group
                }
                elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    foreach ($regserver in $object.RegisteredServers) {
                        Add-DbaRegisteredServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $regserver.Name -ServerName $regserver.ServerName -Description $regserver.Description #-Group $object.Name
                    }
                }
                else {
                    if (-not $object.ServerName) {
                        Stop-Function -Message "Property 'ServerName' not found in InputObject. No servers added." -Continue
                    }
                    
                    Add-DbaRegisteredServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $Group
                }
            }
        }
    }
}