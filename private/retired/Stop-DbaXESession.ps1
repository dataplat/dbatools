function Stop-DbaXESession {
    <#
    .SYNOPSIS
        Stops running Extended Events sessions on SQL Server instances

    .DESCRIPTION
        Stops active Extended Events sessions that are currently collecting diagnostic data or monitoring SQL Server activity. This function helps DBAs manage resource usage by ending sessions that may be consuming disk space, memory, or CPU cycles. You can stop specific sessions by name, stop all user-created sessions while preserving critical system sessions, or use pipeline input from Get-DbaXESession. The function safely checks if sessions are running before attempting to stop them and provides clear feedback about the operation results.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        Specifies the names of specific Extended Events sessions to stop by name. Accepts session names as strings or arrays for multiple sessions.
        Use this when you need to stop particular monitoring sessions while leaving others running, such as stopping a performance troubleshooting session while keeping system health sessions active.

    .PARAMETER AllSessions
        Stops all user-created Extended Events sessions while preserving critical system sessions (AlwaysOn_health, system_health, telemetry_xevents).
        Use this when performing maintenance, reducing resource usage, or cleaning up after troubleshooting activities without disrupting essential SQL Server monitoring.

    .PARAMETER InputObject
        Accepts Extended Events session objects from Get-DbaXESession through the pipeline for stopping sessions.
        Use this approach when you need to filter sessions based on properties like status, start time, or event counts before stopping them, enabling more sophisticated session management workflows.

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
        Author: Doug Meyers

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Stop-DbaXESession

    .OUTPUTS
        Microsoft.SqlServer.Management.XEvent.Session

        Returns one Extended Events session object for each session that was stopped. The session objects reflect the stopped state after the command completes.

        Default display properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the Extended Events session
        - State: The current state of the session (Created, Started, Stopped, or Altered)
        - IsRunning: Boolean indicating if the session is currently running (false after stopping)
        - StartTime: DateTime when the session was started (null if not currently running)
        - DefinitionFileLocation: Path to the XML definition file for the session
        - MaxMemory: Maximum memory in MB allocated to the session
        - EventRetentionMode: How events are retained (AllowSingleEventLoss, AllowMultipleEventLoss, NoEventLoss, or DropOnFullBuffer)

        Additional properties available on the SMO Session object (via Select-Object *):
        - Urn: The Uniform Resource Name for the session object
        - Properties: Collection of session property objects
        - TargetCount: Number of targets associated with the session
        - EventCount: Number of events collected by the session
        - MaxDispatchLatency: Maximum latency in seconds for event dispatch
        - SuspendedEventCount: Number of currently suspended events

    .EXAMPLE
        PS C:\> Stop-DbaXESession -SqlInstance sqlserver2012 -AllSessions

        Stops all Extended Event Session on the sqlserver2014 instance.

    .EXAMPLE
        PS C:\> Stop-DbaXESession -SqlInstance sqlserver2012 -Session xesession1,xesession2

        Stops the xesession1 and xesession2 Extended Event sessions.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sqlserver2012 -Session xesession1 | Stop-DbaXESession

        Stops the sessions returned from the Get-DbaXESession function.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Session')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Position = 1, Mandatory, ParameterSetName = 'Session')]
        [parameter(Position = 1, Mandatory, ParameterSetName = 'All')]
        [DbaInstanceParameter[]]$SqlInstance,

        [parameter(ParameterSetName = 'Session')]
        [parameter(ParameterSetName = 'All')]
        [PSCredential]$SqlCredential,

        [parameter(Mandatory, ParameterSetName = 'Session')]
        [Alias("Sessions")]
        [object[]]$Session,

        [parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$AllSessions,

        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        # Stop each XESession
        function Stop-XESessions {
            [CmdletBinding(SupportsShouldProcess)]
            param ([Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions)

            foreach ($xe in $xeSessions) {
                $instance = $xe.Parent.Name
                $session = $xe.Name
                if ($xe.isRunning) {
                    Write-Message -Level Verbose -Message "Stopping XEvent Session $session on $instance."
                    if ($Pscmdlet.ShouldProcess("$instance", "Stopping XEvent Session $session")) {
                        try {
                            $xe.Stop()
                        } catch {
                            Stop-Function -Message "Could not stop XEvent Session on $instance" -Target $session -ErrorRecord $_ -Continue
                        }
                    }
                } else {
                    Write-Message -Level Warning -Message "$session on $instance is already stopped"
                }
                Get-DbaXESession -SqlInstance $xe.Parent -Session $session
            }
        }
    }

    process {
        if ($InputObject) {
            if ($Pscmdlet.ShouldProcess("Configuring XEvent Sessions to stop")) {
                Stop-XESessions $InputObject
            }
        } else {
            foreach ($instance in $SqlInstance) {
                $xeSessions = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential

                # Filter xesessions based on parameters
                if ($Session) {
                    $xeSessions = $xeSessions | Where-Object { $_.Name -in $Session }
                } elseif ($AllSessions) {
                    $systemSessions = @('AlwaysOn_health', 'system_health', 'telemetry_xevents')
                    $xeSessions = $xeSessions | Where-Object { $_.Name -notin $systemSessions }
                }

                if ($Pscmdlet.ShouldProcess("$instance", "Configuring XEvent Session $xeSessions to Stop")) {
                    Stop-XESessions $xeSessions
                }
            }
        }
    }
}