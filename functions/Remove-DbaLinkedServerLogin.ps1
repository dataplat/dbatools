function Remove-DbaLinkedServerLogin {
    <#
    .SYNOPSIS
        Removes a linked server login.

    .DESCRIPTION
        Removes a linked server login.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LinkedServer
        The name(s) of the linked server(s).

    .PARAMETER LocalLogin
        The name(s) of the linked server login(s).

    .PARAMETER InputObject
        Allows piping from Connect-DbaInstance, Get-DbaLinkedServer, and Get-DbaLinkedServerLogin.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Security, Server
        Author: Adam Lancaster https://github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaLinkedServerLogin

    .EXAMPLE
        PS C:\>Remove-DbaLinkedServerLogin -SqlInstance sql01 -LinkedServer linkedServer1 -LocalLogin linkedServerLogin1 -Confirm:$false

        Removes the linkedServerLogin1 from the linkedServer1 linked server on the sql01 instance.

    .EXAMPLE
        PS C:\>$instance = Connect-DbaInstance -SqlInstance sql01
        PS C:\>$instance | Remove-DbaLinkedServerLogin -LinkedServer linkedServer1 -LocalLogin linkedServerLogin1 -Confirm:$false

        Passes in a SqlInstance via pipeline and removes the linkedServerLogin1 from the linkedServer1 linked server.

    .EXAMPLE
        PS C:\>$linkedServer1 = Get-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1
        PS C:\>$linkedServer1 | Remove-DbaLinkedServerLogin -LocalLogin linkedServerLogin1 -Confirm:$false

        Passes in a linked server via pipeline and removes the linkedServerLogin1.

    .EXAMPLE
        PS C:\>$linkedServerLogin1 = Get-DbaLinkedServerLogin -SqlInstance sql01 -LinkedServer linkedServer1 -LocalLogin linkedServerLogin1
        PS C:\>$linkedServerLogin1 | Remove-DbaLinkedServerLogin -Confirm:$false

        Passes in a linked server login via pipeline and removes it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$LinkedServer,
        [string[]]$LocalLogin,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $linkedServerLoginsToDrop = @()
    }
    process {

        if ($SqlInstance -and (-not $LinkedServer)) {
            Stop-Function -Message "LinkedServer is required when SqlInstance is specified"
            return
        }

        foreach ($instance in $SqlInstance) {
            $linkedServerLoginsToDrop += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential | Get-DbaLinkedServerLogin -LinkedServer $LinkedServer -LocalLogin $LocalLogin
        }

        foreach ($obj in $InputObject) {

            if ($obj -is [Microsoft.SqlServer.Management.Smo.Server]) {

                if (Test-Bound -Not -ParameterName LinkedServer) {
                    Stop-Function -Message "LinkedServer is required" -Continue
                }

                $linkedServerLoginsToDrop += Get-DbaLinkedServerLogin -SqlInstance $obj -LinkedServer $LinkedServer -LocalLogin $LocalLogin
            } elseif ($obj -is [Microsoft.SqlServer.Management.Smo.LinkedServer]) {
                $linkedServerLoginsToDrop += $obj | Get-DbaLinkedServerLogin -LocalLogin $LocalLogin
            } elseif ($obj -is [Microsoft.SqlServer.Management.Smo.LinkedServerLogin]) {
                $linkedServerLoginsToDrop += $obj
            }
        }
    }
    end {

        foreach ($lsLoginToDrop in $linkedServerLoginsToDrop) {

            if ($Pscmdlet.ShouldProcess($lsLoginToDrop.Parent.Name, "Removing the linked server login $($lsLoginToDrop.Name) for the linked server $($lsLoginToDrop.Parent.Name) on $($lsLoginToDrop.Parent.Parent.Name)")) {
                try {
                    $lsLoginToDrop.Drop()
                } catch {
                    Stop-Function -Message "Failure on $($lsLoginToDrop.Parent.Parent.Name) to remove the linked server login $($lsLoginToDrop.Name) for the linked server $($lsLoginToDrop.Parent.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}