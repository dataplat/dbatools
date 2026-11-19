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
        Specifies the name(s) of the linked server(s) to remove from the SQL Server instance.
        Use this to target specific linked servers instead of removing all linked servers.
        Accepts an array of names when you need to remove multiple linked servers in a single operation.

    .PARAMETER InputObject
        Accepts linked server objects from Get-DbaLinkedServer or server instances from Connect-DbaInstance via pipeline.
        Use this when you want to remove linked servers that were previously retrieved with Get-DbaLinkedServer.
        When passing server instances, you must also specify the LinkedServer parameter to identify which linked servers to remove.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Removes all linked server logins associated with the linked server before dropping the linked server itself.
        Use this when the linked server has associated logins that would prevent removal.
        Without this parameter, the removal will fail if any linked server logins exist, requiring you to manually remove them first.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        None

        This command removes linked servers but does not return any output objects. It performs the deletion operation and handles any errors or confirmation prompts via -WhatIf and -Confirm parameters.

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