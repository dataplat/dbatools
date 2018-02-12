function Start-DbaXESession {
    <#
        .SYNOPSIS
            Starts Extended Events sessions.

        .DESCRIPTION
            This script starts Extended Events sessions on a SQL Server instance.

        .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Session
            Only start specific Extended Events sessions.

        .PARAMETER AllSessions
            Start all Extended Events sessions on an instance, ignoring the packaged sessions: AlwaysOn_health, system_health, telemetry_xevents.

        .PARAMETER InputObject
            Internal parameter to support piping from Get-DbaXESession

        .PARAMETER StopAt
            Specifies a datetime at which the session will be stopped. This is done via a self-deleting schedule.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Author: Doug Meyers
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Start-DbaXESession

        .EXAMPLE
            Start-DbaXESession -SqlInstance sqlserver2012 -AllSessions

            Starts all Extended Event Session on the sqlserver2014 instance.

        .EXAMPLE
            Start-DbaXESession -SqlInstance sqlserver2012 -Session xesession1,xesession2

            Starts the xesession1 and xesession2 Extended Event sessions.

        .EXAMPLE
            Start-DbaXESession -SqlInstance sqlserver2012 -Session xesession1,xesession2 -StopAt (Get-Date).AddMinutes(30)

            Starts the xesession1 and xesession2 Extended Event sessions and stops them in 30 minutes.

        .EXAMPLE
            Get-DbaXESession -SqlInstance sqlserver2012 -Session xesession1 | Start-DbaXESession

            Starts the sessions returned from the Get-DbaXESession function.

    #>
    [CmdletBinding(DefaultParameterSetName = 'Session')]
    param (
        [parameter(Position = 1, Mandatory, ParameterSetName = 'Session')]
        [parameter(Position = 1, Mandatory, ParameterSetName = 'All')]
        [Alias("ServerInstance", "SqlServer")]
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
            [CmdletBinding()]
            param ([Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions)

            foreach ($xe in $xeSessions) {
                $instance = $xe.Parent.Name
                $session = $xe.Name
                if (-Not $xe.isRunning) {
                    Write-Message -Level Verbose -Message "Starting XEvent Session $session on $instance."
                    try {
                        $xe.Start()
                    }
                    catch {
                        Stop-Function -Message "Could not start XEvent Session on $instance." -Target $session -ErrorRecord $_ -Continue
                    }
                }
                else {
                    Write-Message -Level Warning -Message "$session on $instance is already running."
                }
                Get-DbaXESession -SqlInstance $xe.Parent -Session $session
            }
        }

        function New-StopJob {
            [CmdletBinding()]
            param (
                [Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions,
                [datetime]$StopAt
            )

            foreach ($xe in $xeSessions) {
                $server = $xe.Parent
                $session = $xe.Name
                $name = "XE Session Stop - $session"

                # Setup the schedule time
                $time = ($StopAt).ToString("HHmmss")

                # Create the schedule
                $schedule = New-DbaAgentSchedule -SqlInstance $server -Schedule $name -FrequencyType Once -StartTime ($StopAt).ToString("HHmmss") -Force

                # Create the job and attach the schedule
                $job = New-DbaAgentJob -SqlInstance $server -Job $name -Schedule $schedule -DeleteLevel Always -Force

                # Create the job step
                $sql = "ALTER EVENT SESSION [$session] ON SERVER STATE = stop;"
                $jobstep = New-DbaAgentJobStep -SqlInstance $server -Job $job -StepName 'T-SQL Stop' -Subsystem TransactSql -Command $sql -Force
            }
        }
    }
    process {
        if ($InputObject) {
            Start-XESessions $InputObject
        }
        else {
            foreach ($instance in $SqlInstance) {
                $xeSessions = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential

                # Filter xeSessions based on parameters
                if ($Session) {
                    $xeSessions = $xeSessions | Where-Object { $_.Name -in $Session }
                }
                elseif ($AllSessions) {
                    $systemSessions = @('AlwaysOn_health', 'system_health', 'telemetry_xevents')
                    $xeSessions = $xeSessions | Where-Object { $_.Name -notin $systemSessions }
                }

                Start-XESessions $xeSessions

                if ($StopAt) {
                    New-StopJob -xeSessions $xeSessions -StopAt $stopat
                }
            }
        }
    }
}