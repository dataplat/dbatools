#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Move-DbaCmsRegServerGroup {
    <#
    .SYNOPSIS
        Moves registered server groups around SQL Server Central Management Server (CMS).

    .DESCRIPTION
        Moves registered server groups around SQL Server Central Management Server (CMS).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Group
        Specifies one or more groups to include from SQL Server Central Management Server.

    .PARAMETER NewGroup
        The new location.

    .PARAMETER InputObject
        Allows results from Get-DbaCmsRegServerGroup to be piped in

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
        https://dbatools.io/Move-DbaCmsRegServerGroup

    .EXAMPLE
        PS C:\> Move-DbaCmsRegServerGroup -SqlInstance sql2012 -Group HR\Development -NewGroup AD\Prod

        Moves the Development group within HR to the Prod group within AD

    .EXAMPLE
        PS C:\> Get-DbaCmsRegServerGroup -SqlInstance sql2017 -Group HR\Development| Move-DbaCmsRegServer -NewGroup Web

        Moves the Development group within HR to the Web group

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Group,
        [parameter(Mandatory)]
        [string]$NewGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Group)) {
            Stop-Function -Message "Group must be specified when using -SqlInstance"
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaCmsRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
        }

        foreach ($regservergroup in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $regservergroup

            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }

            $server = $parentserver.ServerConnection.SqlConnectionObject

            if ($NewGroup -eq 'Default') {
                $groupobject = Get-DbaCmsRegServerGroup -SqlInstance $server -Id 1
            } else {
                $groupobject = Get-DbaCmsRegServerGroup -SqlInstance $server -Group $NewGroup
            }

            Write-Message -Level Verbose -Message "Found $($groupobject.Name) on $($parentserver.ServerConnection.ServerName)"

            if (-not $groupobject) {
                Stop-Function -Message "Group '$NewGroup' not found on $server" -Continue
            }

            if ($Pscmdlet.ShouldProcess($regservergroup.SqlInstance, "Moving $($regservergroup.Name) to $($groupobject.Name)")) {
                try {
                    Write-Message -Level Verbose -Message "Parsing $groupobject"
                    $newname = Get-RegServerGroupReverseParse $groupobject
                    $newname = "$newname\$($regservergroup.Name)"
                    Write-Message -Level Verbose -Message "Executing $($regservergroup.ScriptMove($groupobject).GetScript())"
                    $null = $parentserver.ServerConnection.ExecuteNonQuery($regservergroup.ScriptMove($groupobject).GetScript())
                    Get-DbaCmsRegServerGroup -SqlInstance $server -Group $newname
                    $parentserver.ServerConnection.Disconnect()
                } catch {
                    Stop-Function -Message "Failed to move $($regserver.Name) to $NewGroup on $($regserver.SqlInstance)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Move-DbaRegisteredServerGroup
    }
}