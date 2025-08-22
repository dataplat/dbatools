function New-DbaXESession {
    <#
    .SYNOPSIS
        Creates a new Extended Events session object for programmatic configuration and deployment.

    .DESCRIPTION
        Creates a new Extended Events session object that can be programmatically configured with events, actions, and targets before deployment to SQL Server. This function provides the foundation for building XE sessions through code rather than using predefined templates. The returned session object requires additional configuration using AddEvent(), AddAction(), and AddTarget() methods before calling Create() to deploy it to the server. For most scenarios, Import-DbaXESessionTemplate provides a simpler approach using predefined session configurations, but this function offers complete control when building custom monitoring solutions from scratch.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The Name of the session to be created.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaXESession

    .EXAMPLE
        PS C:\> $session = New-DbaXESession -SqlInstance sql2017 -Name XeSession_Test
        PS C:\> $event = $session.AddEvent("sqlserver.file_written")
        PS C:\> $event.AddAction("package0.callstack")
        PS C:\> $session.Create()

        Returns a new XE Session object from sql2017 then adds an event, an action then creates it.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Name,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Pscmdlet.ShouldProcess($instance, "Creating new XESession")) {
                $SqlConn = $server.ConnectionContext.SqlConnectionObject
                $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
                $store = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection

                $store.CreateSession($Name)
            }
        }
    }
}