#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Import-DbaCmsRegServer {
    <#
    .SYNOPSIS
        Imports registered servers and registered server groups to SQL Server Central Management Server (CMS)

    .DESCRIPTION
        Imports registered servers and registered server groups to SQL Server Central Management Server (CMS)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Group
        Imports to specific group

    .PARAMETER Path
        Optional path to exported reg server XML

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
        https://dbatools.io/Import-DbaCmsRegServer

    .EXAMPLE
        PS C:\> Import-DbaCmsRegServer -SqlInstance sql2012 -Path C:\temp\corp-regservers.xml

        Imports C:\temp\corp-regservers.xml to the CMS on sql2012

    .EXAMPLE
        PS C:\> Import-DbaCmsRegServer -SqlInstance sql2008 -Group hr\Seattle -Path C:\temp\Seattle.xml

        Imports C:\temp\Seattle.xml to Seattle subgroup within the hr group on sql2008

    .EXAMPLE
        PS C:\> Get-DbaCmsRegServer -SqlInstance sql2008, sql2012 | Import-DbaCmsRegServer -SqlInstance sql2017

        Imports all registered servers from sql2008 and sql2012 to sql2017

    .EXAMPLE
        PS C:\> Get-DbaCmsRegServerGroup -SqlInstance sql2008 -Group hr\Seattle | Import-DbaCmsRegServer -SqlInstance sql2017 -Group Seattle

        Imports all registered servers from the hr\Seattle group on sql2008 to the Seattle group on sql2017

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("FullName")]
        [string[]]$Path,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [object]$Group,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            # Prep to import from file
            if ((Test-Bound -ParameterName Path)) {
                $InputObject += Get-ChildItem -Path $Path
            }
            if ((Test-Bound -ParameterName Group) -and (Test-Bound -Not -ParameterName Path)) {
                if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    $groupobject = $Group
                } else {
                    $groupobject = Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                }
                if (-not $groupobject) {
                    Stop-Function -Message "Group $Group cannot be found on $instance" -Target $instance -Continue
                }
            }

            foreach ($object in $InputObject) {
                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {

                    $groupexists = Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $object.Parent.Name
                    if (-not $groupexists) {
                        $groupexists = Add-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Parent.Name
                    }
                    Add-DbaCmsRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $groupexists
                } elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    foreach ($regserver in $object.RegisteredServers) {
                        $groupexists = Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $regserver.Parent.Name
                        if (-not $groupexists) {
                            $groupexists = Add-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Name $regserver.Parent.Name
                        }
                        Add-DbaCmsRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $regserver.Name -ServerName $regserver.ServerName -Description $regserver.Description -Group $groupexists
                    }
                } elseif ($object -is [System.IO.FileInfo]) {
                    if ((Test-Bound -ParameterName Group)) {
                        if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                            $reggroups = $Group
                        } else {
                            $reggroups = Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                        }
                    } else {
                        $reggroups = Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
                    }

                    foreach ($file in $object) {
                        if (-not (Test-Path -Path $file)) {
                            Stop-Function -Message "$file cannot be found" -Target $file -Continue
                        }

                        foreach ($reggroup in $reggroups) {
                            try {
                                Write-Message -Level Verbose -Message "Importing $file to $($reggroup.Name) on $instance"
                                $urnlist = $reggroup.RegisteredServers.Urn.Value
                                $reggroup.Import($file.FullName)
                                Get-DbaCmsRegServer -SqlInstance $instance -SqlCredential $SqlCredential | Where-Object { $_.Urn.Value -notin $urnlist }
                            } catch {
                                Stop-Function -Message "Failure attempting to import $file to $instance" -ErrorRecord $_ -Continue
                            }
                        }
                    }
                } else {
                    if (-not $object.ServerName) {
                        Stop-Function -Message "Property 'ServerName' not found in InputObject. No servers added." -Continue
                    }
                    Add-DbaCmsRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $groupobject
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Import-DbaRegisteredServer
    }
}