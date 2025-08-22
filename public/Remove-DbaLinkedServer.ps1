function Remove-DbaLinkedServer {
    <#
    .SYNOPSIS
        Removes linked servers from SQL Server instances.

    .DESCRIPTION
        Removes one or more linked servers from target SQL Server instances. This function drops the linked server objects from the system catalog, effectively severing the connection between the local and remote servers. When using the -Force parameter, it also removes any associated linked server logins before dropping the linked server itself. This is useful for decommissioning legacy connections, cleaning up unused linked servers during server migrations, or removing connections for security compliance requirements.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LinkedServer
        The name(s) of the linked server(s).

    .PARAMETER InputObject
        Allows piping from Connect-DbaInstance and Get-DbaLinkedServer.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Drops the linked server login(s) associated with the linked server and then drops the linked server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: LinkedServer, Server
        Author: Adam Lancaster, github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaLinkedServer

    .EXAMPLE
        PS C:\>Remove-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1 -Confirm:$false

        Removes the linked server "linkedServer1" from the sql01 instance.

    .EXAMPLE
        PS C:\>Remove-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1 -Confirm:$false -Force

        Removes the linked server "linkedServer1" and the associated linked server logins from the sql01 instance.

    .EXAMPLE
        PS C:\>$linkedServer1 = Get-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1
        PS C:\>$linkedServer1 | Remove-DbaLinkedServer -Confirm:$false

        Passes in a linked server via pipeline and removes it from the sql01 instance.

    .EXAMPLE
        PS C:\>Connect-DbaInstance -SqlInstance sql01 | Remove-DbaLinkedServer -LinkedServer linkedServer1 -Confirm:$false

        Removes the linked server "linkedServer1" from the sql01 instance, which is passed in via pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$LinkedServer,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $linkedServersToDrop = @()
    }
    process {

        foreach ($instance in $SqlInstance) {
            $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        }

        foreach ($obj in $InputObject) {

            if ($obj -is [Microsoft.SqlServer.Management.Smo.Server]) {

                if (Test-Bound -Not -ParameterName LinkedServer) {
                    Stop-Function -Message "LinkedServer is required" -Continue
                }

                foreach ($ls in $LinkedServer) {

                    if ($obj.LinkedServers.Name -notcontains $ls) {
                        Stop-Function -Message "Linked server $ls does not exist on $($obj.Name)" -Continue
                    }

                    $linkedServersToDrop += $obj.LinkedServers[$ls]
                }

            } elseif ($obj -is [Microsoft.SqlServer.Management.Smo.LinkedServer]) {
                $linkedServersToDrop += $obj
            }
        }
    }
    end {

        foreach ($lsToDrop in $linkedServersToDrop) {

            if ($Pscmdlet.ShouldProcess($lsToDrop.Parent.Name, "Removing the linked server $($lsToDrop.Name) on $($lsToDrop.Parent.Name)")) {
                try {
                    $lsToDrop.Drop([boolean]$Force)
                } catch {
                    Stop-Function -Message "Failure on $($lsToDrop.Parent.Name) to remove the linked server $($lsToDrop.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}