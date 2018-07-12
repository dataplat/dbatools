#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Add-DbaRegisteredServerGroup {
    <#
        .SYNOPSIS
            Adds registered server groups to SQL Server Central Management Server (CMS)

        .DESCRIPTION
            Adds registered server groups to SQL Server Central Management Server (CMS). If you need more flexiblity, look into Import-DbaRegisteredServer which
            accepts multiple kinds of input and allows you to add reg servers and groups from different CMSes.

        .PARAMETER SqlInstance
            The target SQL Server instance

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Name
            The name of the registered server group

        .PARAMETER Description
            The description for the registered server group

        .PARAMETER Group
            The SQL Server Central Management Server group. If no groups are specified, the new group will be created at the root.

        .PARAMETER InputObject
            Allows results from Get-DbaRegisteredServerGroup to be piped in

        .PARAMETER IncludeRegisteredServers
            Create the registered servers within the group, too

        .PARAMETER InputObject
            Allows results from Get-DbaRegisteredServerGroup to be piped in

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
            Add-DbaRegisteredServerGroup -SqlInstance sql2012 -Name HR

            Creates a registered server group called HR, in the root of sql2012's CMS

        .EXAMPLE
            Add-DbaRegisteredServerGroup -SqlInstance sql2012, sql2014 -Name subfolder -Group HR

            Creates a registered server group on sql2012 and sql2014 called subfolder within the HR group

    .EXAMPLE
            Get-DbaRegisteredServerGroup -SqlInstance sql2012, sql2014 -Group HR | Add-DbaRegisteredServerGroup -Name subfolder

            Creates a registered server group on sql2012 and sql2014 called subfolder within the HR group of each server
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Name,
        [string]$Description,
        [string]$Group,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must either pipe in a registered server group or specify a sqlinstance"
            return
        }
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
                    
                    Get-DbaRegisteredServerGroup -SqlInstance $parentserver.ServerConnection.SqlConnectionObject -Group (Get-RegServerGroupReverseParse -object $newgroup)
                    $parentserver.ServerConnection.Disconnect()
                }
                catch {
                    Stop-Function -Message "Failed to add $reggroup on $server" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}