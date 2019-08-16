function Remove-DbaRegServer {
    <#
    .SYNOPSIS
        Removes registered servers found in SQL Server Central Management Server (CMS).

    .DESCRIPTION
        Removes registered servers found in SQL Server Central Management Server (CMS).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies one or more names to include. Name is the visible name in SSMS CMS interface (labeled Registered Server Name)

    .PARAMETER ServerName
        Specifies one or more server names to include. Server Name is the actual instance name (labeled Server Name)

    .PARAMETER Group
        Specifies one or more groups to include from SQL Server Central Management Server.

    .PARAMETER InputObject
        Allows results from Get-DbaRegServer to be piped in

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
        https://dbatools.io/Remove-DbaRegServer

    .EXAMPLE
        PS C:\> Remove-DbaRegServer -SqlInstance sql2012 -Group HR, Accounting

        Removes all servers from the HR and Accounting groups on sql2012

    .EXAMPLE
        PS C:\> Remove-DbaRegServer -SqlInstance sql2012 -Group HR\Development

        Removes all servers from the HR and sub-group Development from the CMS on sql2012.

    .EXAMPLE
        PS C:\> Remove-DbaRegServer -SqlInstance sql2012 -Confirm:$false

        Removes all registered servers on sql2012 and turns off all prompting

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$ServerName,
        [string[]]$Group,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer[]]$InputObject,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group -ExcludeGroup $ExcludeGroup -Name $Name -ServerName $ServerName
        }

        if (-not $SqlInstance -and -not $InputObject) {
            $InputObject += Get-DbaRegServer -Group $Group -ExcludeGroup $ExcludeGroup -Name $Name -ServerName $ServerName
        }

        foreach ($regserver in $InputObject) {
            if ($regserver.Source -eq "Azure Data Studio") {
                Stop-Function -Message "You cannot use dbatools to remove or add registered servers in Azure Data Studio" -Continue
            }

            if ($regserver.ID) {
                $defaults = "ComputerName", "InstanceName", "SqlInstance", "Name", "ServerName", "Status"
                $target = $regserver.Parent
            } else {
                $defaults = "Name", "ServerName", "Status"
                $target = "Local Registered Server Groups"
            }

            if ($Pscmdlet.ShouldProcess($target, "Removing $regserver")) {
                $null = $regserver.Drop()

                if ($regserver.ID) {
                    Disconnect-RegServer -Server $regserver.Parent
                }

                try {
                    [pscustomobject]@{
                        ComputerName = $regserver.ComputerName
                        InstanceName = $regserver.InstanceName
                        SqlInstance  = $regserver.SqlInstance
                        Name         = $regserver.Name
                        ServerName   = $regserver.ServerName
                        Status       = "Dropped"
                    } | Select-DefaultView -Property $defaults
                } catch {
                    Stop-Function -Message "Failed to drop $regserver on $target" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}