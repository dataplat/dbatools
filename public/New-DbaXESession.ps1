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
        Specifies the name for the new Extended Events session. Session names must be unique within the SQL Server instance and follow SQL Server identifier naming rules.
        Choose descriptive names that indicate the monitoring purpose, such as "Query_Performance_Monitor" or "Security_Audit_Session".

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.XEvent.Session

        Returns an Extended Events session object that can be further configured with events, actions, and targets before calling Create() to deploy it to the server. The session object is created but not yet persisted until Create() is called.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the Extended Events session
        - Status: Current session status (typically New before Create() is called)
        - StartTime: DateTime when the session was started (null until started)
        - AutoStart: Boolean indicating if the session starts automatically on SQL Server restart
        - State: SMO object state (typically Creating until Create() is called)
        - Targets: Target collection for the session (initially empty)
        - TargetFile: File path(s) where XE trace data will be written (if configured)
        - Events: Events configured in the session (initially empty)
        - MaxMemory: Maximum memory in MB allocated to the session
        - MaxEventSize: Maximum size in MB for individual events

        Additional properties available (from SMO Session object):
        - All standard SMO XEvent.Session properties are accessible via Select-Object *

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

                $session = $store.CreateSession($Name)

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status', 'StartTime', 'AutoStart', 'State', 'Targets', 'TargetFile', 'Events', 'MaxMemory', 'MaxEventSize'
                $session | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                $session | Add-Member -Force -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                $session | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                $session | Select-DefaultView -Property $defaults
            }
        }
    }
}