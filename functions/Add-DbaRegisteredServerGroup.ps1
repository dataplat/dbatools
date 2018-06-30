#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Add-DbaRegisteredServerGroup {
    <#
        .SYNOPSIS
            Adds registered server groups to SQL Server Central Management Server (CMS)

        .DESCRIPTION
            Adds registered server groups to SQL Server Central Management Server (CMS)

        .PARAMETER SqlInstance
            The target SQL Server instance

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Name
            The Group name

        .PARAMETER Description
            Adds a description for the registered server group

        .PARAMETER Group
            The SQL Server Central Management Server group. If no groups are specified, the new group will be created at the root.

        .PARAMETER InputObject
            Allows results from Get-DbaRegisteredServerGroup to be piped in

        .PARAMETER IncludeRegisteredServers
            When a piping a group from another server, also create the registered server

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

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
            https://dbatools.io/Add-DbaRegisteredServerGroup

        .EXAMPLE
            Add-DbaRegisteredServerGroup -SqlInstance sql2012, sql2014 -Name subfolder -Group HR

            Creates a registered server group on sql2012 and sql2014 called subfolder within the HR group

        .EXAMPLE
            Get-DbaRegisteredServerGroup -SqlInstance sql2012 -Group HR | Add-DbaRegisteredServerGroup -SqlInstance sql01

            Creates a registered server group on sql01's CMS
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Name,
        [string]$Description,
        [string]$Group,
        [switch]$IncludeRegisteredServers,
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            if ((Test-Bound -ParameterName Group)) {
                $InputObject += Get-DbaRegisteredServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
            }
            else {
                $InputObject += Get-DbaRegisteredServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
            }
        }

        foreach ($reggroup in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $reggroup
            $server = $parentserver.ServerConnection.ServerInstance.SqlConnectionObject

            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }

            if ($Pscmdlet.ShouldProcess($parentserver.SqlInstance, "Adding $Name")) {
                try {
                    $newgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($reggroup, $Name)
                    $newgroup.Description = $Description
                    $newgroup.Create()

                    if ($IncludeRegisteredServers) {
                        Add-DbaRegisteredServer -SqlInstance $server -InputObject $reggroup.RegisteredServers -Group $newgroup
                    }

                    Get-DbaRegisteredServerGroup -SqlInstance $parentserver.ServerConnection.SqlConnectionObject | Where-Object Id -eq $newgroup.id
                }
                catch {
                    Stop-Function -Message "Failed to add $reggroup on $server" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}