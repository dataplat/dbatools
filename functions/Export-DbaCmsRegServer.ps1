#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Export-DbaCmsRegServer {
    <#
    .SYNOPSIS
        Exports registered servers and registered server groups to file

    .DESCRIPTION
        Exports registered servers and registered server groups to file

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER CredentialPersistenceType
        Used to specify how the login and passwords are persisted. Valid values include None, PersistLoginName and PersistLoginNameAndPassword.

    .PARAMETER Path
        The path to the exported file. If no path is specified, one will be created.

    .PARAMETER InputObject
        Enables piping from Get-DbaCmsRegServer, Get-DbaCmsRegServerGroup, CSVs and other objects.

        If importing from CSV or other object, a column named ServerName is required. Optional columns include Name, Description and Group.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: RegisteredServer, CMS
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaCmsRegServer

    .EXAMPLE
        PS C:\> Export-DbaCmsRegServer -SqlInstance sql2008

        Exports all Registered Server and Registered Server Groups on sql2008 to an automatically generated file name in the current directory

    .EXAMPLE
        PS C:\> Get-DbaCmsRegServer -SqlInstance sql2008, sql2012 | Export-DbaCmsRegServer

        Exports all registered servers on sql2008 and sql2012. Warning - each one will have its own individual file. Consider piping groups.

    .EXAMPLE
        PS C:\> Get-DbaCmsRegServerGroup -SqlInstance sql2008, sql2012 | Export-DbaCmsRegServer

        Exports all registered servers on sql2008 and sql2012, organized by group.

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameter CredentialPersistenceType")]
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
        } else {
            $timeNow = (Get-Date -uformat "%m%d%Y%H%M%S")
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
        }

        foreach ($object in $InputObject) {
            try {
                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]) {
                    $object = Get-DbaCmsRegServerGroup -SqlInstance $object.ServerConnection.SqlConnectionObject -Id 1
                }

                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                    if ((Test-Bound -ParameterName Path -Not)) {
                        $servername = $object.SqlInstance.Replace('\', '$')
                        $regservername = $object.Name.Replace('\', '$')
                        $Path = "$serverName-regserver-$regservername-$timeNow.xml"
                    }
                    $object.Export($Path, $CredentialPersistenceType)
                } elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    if ((Test-Bound -ParameterName Path -Not)) {
                        $servername = $object.SqlInstance.Replace('\', '$')
                        $regservergroup = $object.Name.Replace('\', '$')
                        $Path = "$serverName-reggroup-$regservergroup-$timeNow.xml"
                    }
                    $object.Export($Path, $CredentialPersistenceType)
                } else {
                    Stop-Function -Message "InputObject is not a registered server or server group" -Continue
                }
                Get-ChildItem $Path -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }

    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Export-DbaRegisteredServer
    }
}