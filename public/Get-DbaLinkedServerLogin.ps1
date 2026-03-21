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
        Specifies the name(s) of the linked server(s) to retrieve login mappings from. Required when using SqlInstance parameter.
        Use this to focus on specific linked servers when you have multiple configured on the instance.

    .PARAMETER LocalLogin
        Filters results to only include specific local SQL Server login names that have mappings configured for the linked server.
        Useful when auditing a specific user's access or troubleshooting authentication for particular accounts.

    .PARAMETER ExcludeLocalLogin
        Excludes specific local SQL Server login names from the results, showing all other configured login mappings.
        Use this to hide system accounts or service accounts when focusing on user login mappings.

    .PARAMETER InputObject
        Accepts piped input from Connect-DbaInstance or Get-DbaLinkedServer commands to work with existing connection objects.
        When piping from Get-DbaLinkedServer, the LinkedServer parameter becomes optional since the linked server context is already established.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.LinkedServerLogin

        Returns one LinkedServerLogin object per local login mapping configured on the linked server.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the local SQL Server login
        - RemoteUser: The remote user account on the linked server
        - Impersonate: Boolean indicating if the remote user credentials are impersonated

        Additional properties available (from SMO LinkedServerLogin object):
        - DateLastModified: DateTime when the login mapping was last modified
        - Parent: Reference to the parent LinkedServer object
        - State: Current state of the SMO object (Existing, Creating, Pending, etc.)
        - Urn: The Uniform Resource Name for the object

        All properties from the base SMO object are accessible even though only default properties are displayed without using Select-Object *.

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