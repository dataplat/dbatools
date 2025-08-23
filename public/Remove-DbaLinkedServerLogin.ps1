function Remove-DbaLinkedServerLogin {
    <#
    .SYNOPSIS
        Removes linked server login mappings that define credential relationships between local and remote server logins.

    .DESCRIPTION
        Removes linked server login mappings, which are the credential associations that determine how local SQL Server logins authenticate to remote servers through linked server connections. These mappings control which credentials are used when executing queries against remote servers, so removing them effectively blocks access through that linked server for the specified local login. This is commonly used when decommissioning user access, cleaning up security configurations, or removing entire linked server setups.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LinkedServer
        Specifies the name of the linked server containing the login mappings to remove. This is the linked server object that holds the credential associations between local and remote server logins.
        Use this when you need to remove login mappings from a specific linked server, such as when cleaning up security configurations or decommissioning user access.

    .PARAMETER LocalLogin
        Specifies the local login names whose linked server login mappings should be removed. These are the local SQL Server login accounts that have credential mappings defined for remote server access.
        Use this to remove specific login mappings rather than all mappings for a linked server, such as when a user account is being deactivated or their remote access needs to be revoked.

    .PARAMETER InputObject
        Accepts SQL Server instance objects, linked server objects, or linked server login objects from the pipeline for batch removal operations. Compatible with output from Connect-DbaInstance, Get-DbaLinkedServer, and Get-DbaLinkedServerLogin.
        Use this for pipeline operations when you want to remove login mappings from multiple objects or when chaining commands together for bulk security configuration changes.

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
        Author: Adam Lancaster, github.com/lancasteradam

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

        foreach ($object in $InputObject) {

            if ($object -is [Microsoft.SqlServer.Management.Smo.Server]) {

                if (Test-Bound -Not -ParameterName LinkedServer) {
                    Stop-Function -Message "LinkedServer is required" -Continue
                }

                $linkedServerLoginsToDrop += Get-DbaLinkedServerLogin -SqlInstance $object -LinkedServer $LinkedServer -LocalLogin $LocalLogin
            } elseif ($object -is [Microsoft.SqlServer.Management.Smo.LinkedServer]) {
                $linkedServerLoginsToDrop += $object | Get-DbaLinkedServerLogin -LocalLogin $LocalLogin
            } elseif ($object -is [Microsoft.SqlServer.Management.Smo.LinkedServerLogin]) {
                $linkedServerLoginsToDrop += $object
            }
        }
    }
    end {

        foreach ($lsLoginToDrop in $linkedServerLoginsToDrop) {
            # grab info to be used in output.
            $lsqlinstance = $lsLoginToDrop.Parent.Parent.Name
            $lserver = $lsLoginToDrop.Parent.Name
            $lsqlcomputername = $lsLoginToDrop.Parent.Parent.ComputerName
            $lsqlinstancename = $lsLoginToDrop.Parent.Parent.ServiceName
            $lsloginname = $lsLoginToDrop.Name

            if ($Pscmdlet.ShouldProcess($lsqlinstance, "Removing the linked server login $lsloginname for the linked server $lserver on $lsqlinstance")) {
                try {
                    $lsLoginToDrop.Drop()
                    [PSCustomObject]@{
                        ComputerName = $lsqlcomputername
                        InstanceName = $lsqlinstancename
                        SqlInstance  = $lsqlinstance
                        LinkedServer = $lserver
                        Login        = $lsLoginToDrop.Name
                        Status       = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure on $lsqlinstance to remove the linked server login $lsloginname for the linked server $lserver" -ErrorRecord $_ -Continue
                    [PSCustomObject]@{
                        ComputerName = $lsqlcomputername
                        InstanceName = $lsqlinstancename
                        SqlInstance  = $lsqlinstance
                        LinkedServer = $lserver
                        Login        = $lsLoginToDrop.Name
                        Status       = "Failure"
                    }
                }
            }
        }
    }
}