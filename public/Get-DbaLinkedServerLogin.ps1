function Get-DbaLinkedServerLogin {
    <#
    .SYNOPSIS
        Retrieves linked server login mappings and authentication configurations from SQL Server instances.

    .DESCRIPTION
        Retrieves the login mappings configured for linked servers, showing how local SQL Server logins are mapped to remote server credentials. This function returns details about each login mapping including the local login name, remote user account, and whether impersonation is enabled. Use this to audit linked server security configurations, troubleshoot authentication issues between servers, or document cross-server login relationships for compliance purposes.

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
        The name(s) of the linked server login(s) to include.

    .PARAMETER ExcludeLocalLogin
        The name(s) of the linked server login(s) to exclude

    .PARAMETER InputObject
        Allows piping from Connect-DbaInstance and Get-DbaLinkedServer

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: LinkedServer, Login
        Author: Adam Lancaster, github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaLinkedServerLogin

    .EXAMPLE
        PS C:\>Get-DbaLinkedServerLogin -SqlInstance sql01 -LinkedServer linkedServer1 -LocalLogin login1

        Gets the linked server login "login1" from the linked server "linkedServer1" on sql01.

    .EXAMPLE
        PS C:\>Get-DbaLinkedServerLogin -SqlInstance sql01 -LinkedServer linkedServer1 -ExcludeLocalLogin login2

        Gets the linked server login(s) from the linked server "linkedServer1" on sql01 and excludes the login2 linked server login.

    .EXAMPLE
        PS C:\>(Get-DbaLinkedServer -SqlInstance sql01 -LinkedServer linkedServer1) | Get-DbaLinkedServerLogin -LocalLogin login1

        Gets the linked server login "login1" from the linked server "linkedServer1" on sql01 using a pipeline with the linked server passed in.

    .EXAMPLE
        PS C:\>(Connect-DbaInstance -SqlInstance sql01) | Get-DbaLinkedServerLogin -LinkedServer linkedServer1 -LocalLogin login1

        Gets the linked server login "login1" from the linked server "linkedServer1" on sql01 using a pipeline with the instance passed in.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$LinkedServer,
        [string[]]$LocalLogin,
        [string[]]$ExcludeLocalLogin,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {

        foreach ($instance in $SqlInstance) {

            if (Test-Bound -Not -ParameterName LinkedServer) {
                Stop-Function -Message "LinkedServer is required" -Continue
            }

            $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential | Get-DbaLinkedServer -LinkedServer $LinkedServer
        }

        foreach ($obj in $InputObject) {

            if ($obj -is [Microsoft.SqlServer.Management.Smo.Server]) {

                if (Test-Bound -Not -ParameterName LinkedServer) {
                    Stop-Function -Message "LinkedServer is required" -Continue
                }

                $ls = Get-DbaLinkedServer -SqlInstance $obj -LinkedServer $LinkedServer

            } elseif ($obj -is [Microsoft.SqlServer.Management.Smo.LinkedServer]) {
                $ls = $obj
            }

            $linkedServerLogins = $ls.LinkedServerLogins

            if ($LocalLogin) {
                $linkedServerLogins = $linkedServerLogins | Where-Object { $_.Name -in $LocalLogin }
            }

            if ($ExcludeLocalLogin) {
                $linkedServerLogins = $linkedServerLogins | Where-Object { $_.Name -notin $ExcludeLocalLogin }
            }

            foreach ($lsLogin in $linkedServerLogins) {
                Add-Member -Force -InputObject $lsLogin -MemberType NoteProperty -Name ComputerName -value $ls.parent.ComputerName
                Add-Member -Force -InputObject $lsLogin -MemberType NoteProperty -Name InstanceName -value $ls.parent.ServiceName
                Add-Member -Force -InputObject $lsLogin -MemberType NoteProperty -Name SqlInstance -value $ls.parent.DomainInstanceName

                Select-DefaultView -InputObject $lsLogin -Property ComputerName, InstanceName, SqlInstance, Name, RemoteUser, Impersonate
            }
        }
    }
}