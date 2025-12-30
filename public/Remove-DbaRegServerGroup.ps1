function Remove-DbaRegServerGroup {
    <#
    .SYNOPSIS
        Removes server groups from SQL Server Central Management Server (CMS).

    .DESCRIPTION
        Deletes specified server groups from Central Management Server, including all nested subgroups and registered servers within those groups. This permanently removes the organizational structure you've built in CMS, so use with caution. The function works with both local registered servers and CMS-based groups, and supports piping from Get-DbaRegServerGroup for targeted removal operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies the name of one or more server groups to remove from Central Management Server or local registered servers. Supports hierarchical paths like "HR\Development" to target subgroups within parent groups.
        Use this when you know the exact group names to delete and want to remove specific organizational structures from your CMS or local registered server configuration.

    .PARAMETER InputObject
        Accepts ServerGroup objects from Get-DbaRegServerGroup for pipeline operations. This allows you to first filter or query specific server groups, then remove them in a controlled manner.
        Use this approach when you need to perform complex filtering, review groups before deletion, or process large numbers of groups with conditional logic.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per server group removed.

        For server groups on Central Management Server (CMS), default display properties are:
        - ComputerName: The computer name of the CMS instance
        - InstanceName: The instance name of the CMS
        - SqlInstance: The full instance name of the CMS (computer\instance)
        - Name: The name of the server group that was removed
        - Status: "Dropped" if successful

        For local registered server groups, default display properties are:
        - Name: The name of the server group that was removed
        - Status: "Dropped" if successful

        Note: The PSCustomObject includes all properties listed above regardless of display mode. Use Select-Object * to see all properties when needed.

    .LINK
        https://dbatools.io/Remove-DbaRegServerGroup

    .EXAMPLE
        PS C:\> Remove-DbaRegServerGroup -SqlInstance sql2012 -Group HR, Accounting

        Removes the HR and Accounting groups on sql2012

    .EXAMPLE
        PS C:\> Remove-DbaRegServerGroup -SqlInstance sql2012 -Group HR\Development -Confirm:$false

        Removes the Development subgroup within the HR group on sql2012 and turns off all prompting

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Group")]
        [string[]]$Name,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Name
        }

        if (-not $SqlInstance -and -not $InputObject) {
            $InputObject += Get-DbaRegServerGroup -Group $Name
        }

        foreach ($regservergroup in $InputObject) {
            if ($regservergroup.ID) {
                $parentserver = Get-RegServerParent -InputObject $regservergroup
                $target = $parentserver.DomainInstanceName
                if ($null -eq $parentserver) {
                    Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
                }
                $defaults = "ComputerName", "InstanceName", "SqlInstance", "Name", "Status"
            } else {
                $target = "Local Registered Servers"
                $defaults = "Name", "Status"
            }

            if ($Pscmdlet.ShouldProcess($target, "Removing $($regservergroup.Name) Group")) {
                if ($regservergroup.Source -eq "Azure Data Studio") {
                    Stop-Function -Message "You cannot use dbatools to remove or add registered server groups in Azure Data Studio" -Continue
                }

                # try to avoid 'Collection was modified after the enumerator was instantiated' issue
                if ($regservergroup.ID) {
                    $null = $parentserver.ServerConnection.ExecuteNonQuery($regservergroup.ScriptDrop().GetScript())
                    $parentserver.ServerConnection.Disconnect()
                } else {
                    $regservergroup.Drop()
                }

                try {
                    [PSCustomObject]@{
                        ComputerName = $parentserver.ComputerName
                        InstanceName = $parentserver.InstanceName
                        SqlInstance  = $parentserver.SqlInstance
                        Name         = $regservergroup.Name
                        Status       = "Dropped"
                    } | Select-DefaultView -Property $defaults
                } catch {
                    Stop-Function -Message "Failed to drop $regservergroup on $parentserver" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}