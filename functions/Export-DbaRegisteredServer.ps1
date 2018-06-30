#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Export-DbaRegisteredServer {
    <#
        .SYNOPSIS
            Exports registered servers and registered server groups to file

        .DESCRIPTION
            Exports registered servers and registered server groups to file

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Group
            Imports to specific group

        .PARAMETER CredentialPersistenceType
            Used to specify how the login and passwords are persisted. Valid values include None, PersistLoginName and PersistLoginNameAndPassword.

        .PARAMETER Path
            The path to the exported file. If no path is specified, one will be created.

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
            https://dbatools.io/Export-DbaRegisteredServer

        .EXAMPLE
            Export-DbaRegisteredServer -SqlInstance sqlserver2014a

            Gets a list of servers from the CMS on sqlserver2014a, using Windows Credentials.

        .EXAMPLE
            Export-DbaRegisteredServer -SqlInstance sqlserver2014a -IncludeSelf

            Gets a list of servers from the CMS on sqlserver2014a and includes sqlserver2014a in the output results.

        .EXAMPLE
            Export-DbaRegisteredServer -SqlInstance sqlserver2014a -SqlCredential $credential | Select-Object -Unique -ExpandProperty ServerName

            Returns only the server names from the CMS on sqlserver2014a, using SQL Authentication to authenticate to the server.

        .EXAMPLE
            Export-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR, Accounting

            Gets a list of servers in the HR and Accounting groups from the CMS on sqlserver2014a.

        .EXAMPLE
            Export-DbaRegisteredServer -SqlInstance sqlserver2014a -Group HR\Development

            Returns a list of servers in the HR and sub-group Development from the CMS on sqlserver2014a.
    #>
    [CmdletBinding()]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [string]$Path,
        [ValidateSet("None", "PersistLoginName", "PersistLoginNameAndPassword")]
        [string]$CredentialPersistenceType = "None",
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -ParameterName Path)) {
            if ($Path -notmatch '\\') {
                $Path = ".\$Path"
            }

            $directory = Split-Path $Path
            if (-not (Test-Path $directory)) {
                New-Item -Path $directory -ItemType Directory
            }
        }
        else {
            $timeNow = (Get-Date -uformat "%m%d%Y%H%M%S")
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRegisteredServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
        }

        foreach ($object in $InputObject) {
            try {
                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]) {
                    $object = Get-DbaRegisteredServerGroup -SqlInstance $object.ServerConnection.SqlConnectionObject -Id 1
                }

                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                    if ((Test-Bound -ParameterName Path -Not)) {
                        $servername = $object.SqlInstance
                        $regservername = $object.Name.Replace('\','$')
                        $Path = "$serverName-regserver-$regservername-$timeNow.xml"
                    }
                    $object.Export($Path, 0)
                }
                elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    if ((Test-Bound -ParameterName Path -Not)) {
                        $servername = $object.SqlInstance
                        $regservergroup = $object.Name.Replace('\', '$')
                        $Path = "$serverName-reggroup-$regservergroup-$timeNow.xml"
                    }
                    $object.Export($Path, 0)
                }
                else {
                    Stop-Function -Message "InputObject is not a registered server or server group" -Continue
                }
                Get-ChildItem $Path
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}