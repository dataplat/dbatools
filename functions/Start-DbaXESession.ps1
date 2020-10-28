function Start-DbaXESession {
    <#
    .SYNOPSIS
        Starts Extended Events sessions.

    .DESCRIPTION
        This script starts Extended Events sessions on a SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        Only start specific Extended Events sessions.

    .PARAMETER AllSessions
        Start all Extended Events sessions on an instance, ignoring the packaged sessions: AlwaysOn_health, system_health, telemetry_xevents.

    .PARAMETER InputObject
        Internal parameter to support piping from Get-DbaXESession

    .PARAMETER StopAt
        Specifies a datetime at which the session will be stopped. This is done via a self-deleting schedule.

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

        function New-StopJob {
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions,
                [datetime]$StopAt
            )

            foreach ($xe in $xeSessions) {
                $server = $xe.Parent
                $session = $xe.Name
                $name = "XE Session Stop - $session"
                if ($Pscmdlet.ShouldProcess("$Server", "Making New XEvent StopJob for $session")) {
                    # Setup the schedule time

                    # Create the schedule
                    $StartDateDatePart = Get-Date -Date $StopAt -format 'yyyyMMdd'
                    $StartDateTimePart = Get-Date -Date $StopAt -format 'HHmmss'
                    $schedule = New-DbaAgentSchedule -SqlInstance $server -Schedule $name -FrequencyType Once -StartDate $StartDateDatePart -StartTime $StartDateTimePart -Force

                    # Create the job and attach the schedule
                    $job = New-DbaAgentJob -SqlInstance $server -Job $name -Schedule $schedule -DeleteLevel Always -Force

                    # Create the job step
                    $sql = "ALTER EVENT SESSION [$session] ON SERVER STATE = stop;"
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
                    Start-XESessions $xeSessions

                    if ($StopAt) {
                        New-StopJob -xeSessions $xeSessions -StopAt $StopAt
                    }
                }
            }
        }
    }
}