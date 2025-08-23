function Add-DbaRegServerGroup {
    <#
    .SYNOPSIS
        Creates organizational server groups within SQL Server Central Management Server (CMS)

    .DESCRIPTION
        Creates new server groups in SQL Server Central Management Server to organize registered servers into logical hierarchies. This allows DBAs to group servers by environment, application, location, or any other classification system for easier management at scale. Supports nested group structures using backslash notation (Group\SubGroup) and automatically creates parent groups if they don't exist. If you need to import existing groups and servers from other sources, use Import-DbaRegServer instead.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies the name for the new server group within Central Management Server. Use descriptive names that reflect your organizational structure like 'Production', 'Development', or 'HR-Databases'.
        Group names can include backslashes to create nested hierarchies (e.g., 'Production\WebServers' creates a WebServers subgroup under Production).

    .PARAMETER Description
        Provides additional details about the server group's purpose or contents. Use this to document the group's role, maintenance schedules, or contact information.
        Helpful for team environments where multiple DBAs need to understand each group's function.

    .PARAMETER Group
        Specifies the parent group where the new server group will be created. If omitted, creates the group at the root level of Central Management Server.
        Use backslash notation to specify nested paths like 'Production\WebServers' - this automatically creates any missing parent groups in the hierarchy.

    .PARAMETER InputObject
        Accepts server group objects from Get-DbaRegServerGroup through the pipeline. Use this when you need to create subgroups within existing groups from multiple CMS instances.
        Enables bulk operations where you can pipe existing groups and create new subgroups within each one simultaneously.

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
        https://dbatools.io/Add-DbaRegServerGroup

    .EXAMPLE
        PS C:\> Add-DbaRegServerGroup -SqlInstance sql2012 -Name HR

        Creates a registered server group called HR, in the root of sql2012's CMS

    .EXAMPLE
        PS C:\> Add-DbaRegServerGroup -SqlInstance sql2012, sql2014 -Name sub-folder -Group HR

        Creates a registered server group on sql2012 and sql2014 called sub-folder within the HR group

    .EXAMPLE
        PS C:\> Get-DbaRegServerGroup -SqlInstance sql2012, sql2014 -Group HR | Add-DbaRegServerGroup -Name sub-folder

        Creates a registered server group on sql2012 and sql2014 called sub-folder within the HR group of each server

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
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
        foreach ($instance in $SqlInstance) {
            if ((Test-Bound -ParameterName Group)) {
                $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
            } else {
                $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
            }
        }

        if (-not $SqlInstance -and -not $InputObject) {
            if ((Test-Bound -ParameterName Group)) {
                $InputObject += Get-DbaRegServerGroup -Group $Group
            } else {
                $InputObject += Get-DbaRegServerGroup -Id 1
            }
        }

        foreach ($reggroup in $InputObject) {
            if ($reggroup.Source -eq "Azure Data Studio") {
                Stop-Function -Message "You cannot use dbatools to remove or add registered server groups in Azure Data Studio" -Continue
            }

            $currentInstance = $reggroup.ParentServer

            if ($reggroup.ID) {
                $target = $reggroup.Parent
            } else {
                $target = "Local Registered Server Groups"
            }

            if ($Pscmdlet.ShouldProcess($target, "Adding $Name")) {
                try {
                    $groupList = $Name -split '\\'
                    foreach ($group in $groupList) {
                        if ($null -eq $reggroup.ServerGroups[$group]) {
                            $newGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($reggroup, $group)
                            $newGroup.create()
                            $reggroup.refresh()
                        } else {
                            Write-Message -Level Verbose -Message "Group $group already exists. Will continue."
                            $newGroup = $reggroup.ServerGroups[$group]
                        }
                        $reggroup = $reggroup.ServerGroups[$group]
                    }
                    $newgroup.Description = $Description
                    $newgroup.Alter()

                    Get-DbaRegServerGroup -SqlInstance $currentInstance -Group (Get-RegServerGroupReverseParse -object $newgroup)
                    if ($currentInstance.ConnectionContext) {
                        $currentInstance.ConnectionContext.Disconnect()
                    }
                } catch {
                    Stop-Function -Message "Failed to add $reggroup" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}