function Move-DbaRegServerGroup {
    <#
    .SYNOPSIS
        Moves registered server groups to different parent groups within SQL Server Central Management Server (CMS)

    .DESCRIPTION
        Moves registered server groups to new locations within your Central Management Server hierarchy. This lets you reorganize your CMS group structure without using SQL Server Management Studio manually. You can move groups between different parent groups or relocate them to the root level, helping you maintain organized server collections as your environment grows or changes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Group
        Specifies the registered server group(s) to move within your Central Management Server hierarchy. Accepts group paths like 'HR\Development' or 'Production\WebServers'.
        Use this when you need to select specific groups to relocate rather than piping group objects from Get-DbaRegServerGroup.

    .PARAMETER NewGroup
        Specifies the destination group where the selected groups will be moved. Accepts group paths like 'AD\Prod' or 'Web', or use 'Default' to move to the root level.
        The destination group must already exist in the Central Management Server hierarchy.

    .PARAMETER InputObject
        Accepts registered server group objects from Get-DbaRegServerGroup for pipeline operations. Use this when you want to filter or manipulate groups before moving them.
        This parameter enables advanced scenarios like moving multiple groups based on complex criteria or properties.

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
        https://dbatools.io/Move-DbaRegServerGroup

    .OUTPUTS
        Microsoft.SqlServer.Management.RegisteredServers.ServerGroup

        Returns one ServerGroup object for the group that was successfully moved to its new location. The object represents the moved group at its new position within the Central Management Server hierarchy.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the CMS host
        - InstanceName: The SQL Server instance name of the CMS
        - SqlInstance: The full SQL Server instance name in computer\instance format
        - Name: The name of the moved server group
        - DisplayName: Display name of the server group for UI presentation
        - Description: Text description of the group's purpose or contents
        - ServerGroups: Collection of child server groups nested under this group
        - RegisteredServers: Collection of registered servers that belong to this group

        All properties from the base SMO ServerGroup object are accessible using Select-Object *, including Urn, Parent, ParentServer, and other internal properties.

    .EXAMPLE
        PS C:\> Move-DbaRegServerGroup -SqlInstance sql2012 -Group HR\Development -NewGroup AD\Prod

        Moves the Development group within HR to the Prod group within AD

    .EXAMPLE
        PS C:\> Get-DbaRegServerGroup -SqlInstance sql2017 -Group HR\Development| Move-DbaRegServerGroup -NewGroup Web

        Moves the Development group within HR to the Web group

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
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
            $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
        }

        foreach ($regservergroup in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $regservergroup

            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }

            $server = $regservergroup.ParentServer

            if ($NewGroup -eq 'Default') {
                $groupobject = Get-DbaRegServerGroup -SqlInstance $server -Id 1
            } else {
                $groupobject = Get-DbaRegServerGroup -SqlInstance $server -Group $NewGroup
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
                    Get-DbaRegServerGroup -SqlInstance $server -Group $newname
                    $parentserver.ServerConnection.Disconnect()
                } catch {
                    Stop-Function -Message "Failed to move $($regserver.Name) to $NewGroup on $($regserver.SqlInstance)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}