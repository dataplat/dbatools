function Remove-DbaRegServerGroup {
    <#
    .SYNOPSIS
        Gets list of Server Groups objects stored in SQL Server Central Management Server (CMS).

    .DESCRIPTION
        Returns an array of Server Groups found in the CMS.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies one or more groups to include from SQL Server Central Management Server.

    .PARAMETER InputObject
        Allows results from Get-DbaRegServerGroup to be piped in

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
                    [pscustomobject]@{
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