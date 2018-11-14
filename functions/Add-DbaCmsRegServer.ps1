#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Add-DbaCmsRegServer {
    <#
    .SYNOPSIS
        Adds registered servers to SQL Server Central Management Server (CMS)

    .DESCRIPTION
        Adds registered servers to SQL Server Central Management Server (CMS). If you need more flexiblity, look into Import-DbaCmsRegServer which
        accepts multiple kinds of input and allows you to add reg servers from different CMSes.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER ServerName
        Server Name is the actual SQL instance name (labeled Server Name)

    .PARAMETER Name
        Name is basically the nickname in SSMS CMS interface (labeled Registered Server Name)

    .PARAMETER Description
        Adds a description for the registered server

    .PARAMETER Group
        Adds the registered server to a specific group.

    .PARAMETER InputObject
        Allows the piping of a registered server group

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

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
        https://dbatools.io/Add-DbaCmsRegServer

    .EXAMPLE
        PS C:\> Add-DbaCmsRegServer -SqlInstance sql2008 -ServerName sql01

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, the name "sql01" will be visible.

    .EXAMPLE
        PS C:\> Add-DbaCmsRegServer -SqlInstance sql2008 -ServerName sql01 -Name "The 2008 Clustered Instance" -Description "HR's Dedicated SharePoint instance"

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, "The 2008 Clustered Instance" will be visible.
        Clearly this is hard to explain ;)

    .EXAMPLE
        PS C:\> Add-DbaCmsRegServer -SqlInstance sql2008 -ServerName sql01 -Group hr\Seattle

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, the name "sql01" will be visible within the Seattle group which is in the hr group.

    .EXAMPLE
        PS C:\> Get-DbaCmsRegServerGroup -SqlInstance sql2008 -Group hr\Seattle | Add-DbaCmsRegServer -ServerName sql01111

        Creates a registered server on sql2008's CMS which points to the SQL Server, sql01. When scrolling in CMS, the name "sql01" will be visible within the Seattle group which is in the hr group.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$ServerName,
        [string]$Name = $ServerName,
        [string]$Description,
        [object]$Group,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must either pipe in a registered server group or specify a sqlinstance"
            return
        }

        # double check in case a null name was bound
        if (-not $Name) {
            $Name = $ServerName
        }

        foreach ($instance in $SqlInstance) {
            if (($Group)) {
                if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    $InputObject += Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group.Name
                } else {
                    $InputObject += Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                }
            } else {
                $InputObject += Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
            }

            if (-not $InputObject) {
                Stop-Function -Message "No matching groups found on $instance" -Continue
            }
        }

        foreach ($reggroup in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $reggroup

            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }

            $server = $parentserver.ServerConnection.SqlConnectionObject

            if ($Pscmdlet.ShouldProcess($parentserver.SqlInstance, "Adding $ServerName")) {
                try {
                    $newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($reggroup, $Name)
                    $newserver.ServerName = $ServerName
                    $newserver.Description = $Description
                    $newserver.Create()

                    Get-DbaCmsRegServer -SqlInstance $server -Name $Name -ServerName $ServerName
                } catch {
                    Stop-Function -Message "Failed to add $ServerName on $($parentserver.SqlInstance)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Add-DbaRegisteredServer
    }
}