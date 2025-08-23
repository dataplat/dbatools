function Start-DbaXESession {
    <#
    .SYNOPSIS
        Starts Extended Events sessions on SQL Server instances for monitoring and troubleshooting.

    .DESCRIPTION
        Activates Extended Events sessions that have been created but are not currently running. Extended Events sessions are SQL Server's lightweight monitoring framework used for troubleshooting performance issues, security auditing, and capturing specific database activity patterns.

        The function can start individual sessions by name, all user-created sessions at once, or sessions scheduled to start and stop at specific times. When using -AllSessions, it automatically excludes built-in system sessions (AlwaysOn_health, system_health, telemetry_xevents) so you don't accidentally interfere with SQL Server's internal monitoring.

        For scheduled operations, the function creates temporary SQL Agent jobs that execute at the specified times and then delete themselves. This is particularly useful for capturing data during specific time windows or off-hours troubleshooting sessions.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        Specifies the names of specific Extended Events sessions to start. Accepts multiple session names as an array.
        Use this when you need to start only certain sessions rather than all user-created sessions on the instance.

    .PARAMETER AllSessions
        Starts all user-created Extended Events sessions on the instance while excluding system sessions (AlwaysOn_health, system_health, telemetry_xevents).
        Use this when you want to activate all custom monitoring sessions without interfering with SQL Server's built-in diagnostics.

    .PARAMETER InputObject
        Accepts Extended Events session objects from Get-DbaXESession for pipeline operations.
        Use this when you need to filter sessions with Get-DbaXESession first, then start only the matching sessions.

    .PARAMETER StartAt
        Schedules the Extended Events sessions to start at a specific date and time using a temporary SQL Agent job.
        The command returns immediately while the job handles starting sessions at the scheduled time, useful for capturing activity during specific time windows.

    .PARAMETER StopAt
        Schedules the Extended Events sessions to stop at a specific date and time using a temporary SQL Agent job.
        Use this with StartAt or on already running sessions to create time-bounded monitoring windows for troubleshooting specific issues.

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
        https://dbatools.io/Start-DbaXESession

    .EXAMPLE
        PS C:\> Start-DbaXESession -SqlInstance sqlserver2012 -AllSessions

        Starts all Extended Event Session on the sqlserver2014 instance.

    .EXAMPLE
        PS C:\> Start-DbaXESession -SqlInstance sqlserver2012 -Session xesession1,xesession2

        Starts the xesession1 and xesession2 Extended Event sessions.

    .EXAMPLE
        PS C:\> Start-DbaXESession -SqlInstance sqlserver2012 -Session xesession1,xesession2 -StopAt (Get-Date).AddMinutes(30)

        Starts the xesession1 and xesession2 Extended Event sessions and stops them in 30 minutes.

    .EXAMPLE
        PS C:\> Start-DbaXESession -SqlInstance sqlserver2012 -Session AlwaysOn_health -StartAt (Get-Date).AddMinutes(1)

        Starts the AlwaysOn_health Extended Event sessions in 1 minute. The command will return immediately.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sqlserver2012 -Session xesession1 | Start-DbaXESession

        Starts the sessions returned from the Get-DbaXESession function.

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
        [datetime]$StartAt,
        [datetime]$StopAt,
        [parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$AllSessions,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        # Start each XESession
        function Start-XESessions {
            [CmdletBinding(SupportsShouldProcess)]
            param ([Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions)

            foreach ($xe in $xeSessions) {
                $instance = $xe.Parent.Name
                $session = $xe.Name

                if (-Not $xe.isRunning) {
                    Write-Message -Level Verbose -Message "Starting XEvent Session $session on $instance."
                    if ($Pscmdlet.ShouldProcess("$instance", "Starting XEvent Session $session")) {
                        try {
                            $xe.Start()
                        } catch {
                            Stop-Function -Message "Could not start XEvent Session on $instance." -Target $session -ErrorRecord $_ -Continue
                        }
                    }
                } else {
                    Write-Message -Level Warning -Message "$session on $instance is already running."
                }
                Get-DbaXESession -SqlInstance $xe.Parent -Session $session
            }
        }

        function New-Job {
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions,
                [string]$Action,
                [datetime]$At
            )

            foreach ($xe in $xeSessions) {
                $server = $xe.Parent
                $session = $xe.Name
                $name = "XE Session $Action - $session"
                Write-Message -Level Verbose -Message "Making New XEvent Job for $Action of $session on $server"
                if ($Pscmdlet.ShouldProcess("$server", "Making New XEvent Job for $Action of $session")) {
                    # Setup the schedule time

                    # Create the schedule
                    $StartDateDatePart = Get-Date -Date $At -format 'yyyyMMdd'
                    $StartDateTimePart = Get-Date -Date $At -format 'HHmmss'
                    $schedule = New-DbaAgentSchedule -SqlInstance $server -Schedule $name -FrequencyType Once -StartDate $StartDateDatePart -StartTime $StartDateTimePart -Force

                    # Create the job and attach the schedule
                    $job = New-DbaAgentJob -SqlInstance $server -Job $name -Schedule $schedule -DeleteLevel Always -Force

                    # Create the job step
                    $sql = "ALTER EVENT SESSION [$session] ON SERVER STATE = $Action;"
                    #Variable $jobstep marked as unused by PSScriptAnalyzer replace with $null to catch output
                    $null = New-DbaAgentJobStep -SqlInstance $server -Job $job -StepName 'T-SQL Stop' -Subsystem TransactSql -Command $sql -Force
                }
            }
        }
    }
    process {
        if ($InputObject) {
            Start-XESessions $InputObject
        } else {
            foreach ($instance in $SqlInstance) {
                $xeSessions = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential

                # Filter xeSessions based on parameters
                if ($Session) {
                    $xeSessions = $xeSessions | Where-Object { $_.Name -in $Session }
                } elseif ($AllSessions) {
                    $systemSessions = @('AlwaysOn_health', 'system_health', 'telemetry_xevents')
                    $xeSessions = $xeSessions | Where-Object { $_.Name -notin $systemSessions }
                }

                if ($Pscmdlet.ShouldProcess("$instance", "Configuring XEvent Session $session to start")) {
                    if ($StartAt) {
                        New-Job -xeSessions $xeSessions -Action START -At $StartAt
                        $xeSessions
                    } else {
                        Start-XESessions $xeSessions
                    }

                    if ($StopAt) {
                        New-Job -xeSessions $xeSessions -Action STOP -At $StopAt
                    }
                }
            }
        }
    }
}