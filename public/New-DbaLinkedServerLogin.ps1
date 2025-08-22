function New-DbaLinkedServerLogin {
    <#
    .SYNOPSIS
        Creates authentication mappings between local and remote logins for linked server connections.

    .DESCRIPTION
        Creates linked server login mappings that define how local SQL Server logins authenticate to remote servers during distributed queries. You can either map specific local logins to remote credentials or configure impersonation where local logins use their own credentials. This eliminates the need to hardcode passwords in applications that query across linked servers and provides centralized authentication management for cross-server operations.

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
        Specifies the local login name. This parameter is required in all scenarios.

    .PARAMETER RemoteUser
        Specifies the remote login name.

    .PARAMETER RemoteUserPassword
        Specifies the remote login password as a secure string. NOTE: passwords are sent to the SQL Server instance in plain text. Check with your security administrator before using this parameter. View the documentation for sp_addlinkedsrvlogin for more details.

    .PARAMETER Impersonate
        Specifies if the local login credentials should be used instead of the remote login credentials.

    .PARAMETER InputObject
        Allows piping from Get-DbaLinkedServer.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

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
        https://dbatools.io/New-DbaLinkedServerLogin

    .EXAMPLE
        PS C:\>New-DbaLinkedServerLogin -SqlInstance sql01 -LinkedServer linkedServer1 -LocalLogin localUser1 -RemoteUser remoteUser1 -RemoteUserPassword <password>

        Creates a new linked server login and maps the local login testuser1 to the remote login testuser2. This linked server login is created on the sql01 instance for the linkedServer1 linked server.

        NOTE: passwords are sent to the SQL Server instance in plain text. Check with your security administrator before using the command with the RemoteUserPassword parameter. View the documentation for sp_addlinkedsrvlogin for more details.

    .EXAMPLE
        PS C:\>New-DbaLinkedServerLogin -SqlInstance sql01 -LinkedServer linkedServer1 -Impersonate

        Creates a mapping for all local logins on sql01 to connect using their own credentials to the linked server linkedServer1.

    .EXAMPLE
        PS C:\>Get-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1 | New-DbaLinkedServerLogin -LinkedServer linkedServer1 -LocalLogin testuser1 -RemoteUser testuser2 -RemoteUserPassword <password>

        Creates a new linked server login and maps the local login testuser1 to the remote login testuser2. This linked server login is created on the sql01 instance for the linkedServer1 linked server. The linkedServer1 instance is passed in via pipeline.

        NOTE: passwords are sent to the SQL Server instance in plain text. Check with your security administrator before using the command with the RemoteUserPassword parameter. View the documentation for sp_addlinkedsrvlogin for more details.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$LinkedServer,
        [string]$LocalLogin,
        [string]$RemoteUser,
        [Security.SecureString]$RemoteUserPassword,
        [switch]$Impersonate,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.LinkedServer[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance -and (-not $LinkedServer)) {
            Stop-Function -Message "LinkedServer is required when SqlInstance is specified"
            return
        }

        if (-not $LocalLogin) {
            Stop-Function -Message "LocalLogin is required in all scenarios"
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaLinkedServer -SqlInstance $instance -SqlCredential $SqlCredential -LinkedServer $LinkedServer
        }

        foreach ($lnkSrv in $InputObject) {

            if ($Pscmdlet.ShouldProcess($($lnkSrv.Parent.Name), "Creating the linked server login on $($lnkSrv.Parent.Name)")) {
                try {
                    $newLinkedServerLogin = New-Object Microsoft.SqlServer.Management.Smo.LinkedServerLogin
                    $newLinkedServerLogin.Parent = $lnkSrv

                    if (Test-Bound LocalLogin) {
                        $newLinkedServerLogin.Name = $LocalLogin
                    }

                    if (Test-Bound RemoteUser) {
                        $newLinkedServerLogin.RemoteUser = $RemoteUser
                    }

                    if (Test-Bound RemoteUserPassword) {
                        $newLinkedServerLogin.SetRemotePassword(($RemoteUserPassword | ConvertFrom-SecurePass))
                    }

                    $newLinkedServerLogin.Impersonate = [boolean]$Impersonate

                    $newLinkedServerLogin.Create()

                    $lnkSrv | Get-DbaLinkedServerLogin -LocalLogin $LocalLogin

                } catch {
                    Stop-Function -Message "Failure on $($lnkSrv.Parent.Name) to create the linked server login for $lnkSrv" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}