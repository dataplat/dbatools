function Stop-DbaXESession {
    <#
    .SYNOPSIS
    Stops Extended Events sessions.

    .DESCRIPTION
    This script stops Extended Events sessions on a SQL Server instance.

    .PARAMETER SqlInstance
    The SQL Instances that you're connecting to.

    .PARAMETER SqlCredential
    Credential object used to connect to the SQL Server as a different user

    .PARAMETER Session
    Only stop specific Extended Events sessions.

    .PARAMETER AllSessions
    Stop all Extended Events sessions on an instance, ignoring the packaged sessions: AlwaysOn_health, system_health, telemetry_xevents.

    .PARAMETER SessionCollection
    Internal parameter to support piping from Get-DbaXESession

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Xevent
    Author: Doug Meyers
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Stop-DbaXESession

    .EXAMPLE
    Stop-DbaXESession -SqlInstance sqlserver2012 -AllSessions

    Stops all Extended Event Session on the sqlserver2014 instance.

    .EXAMPLE
    Stop-DbaXESession -SqlInstance sqlserver2012 -Session xesession1,xesession2

    Stops the xesession1 and xesession2 Extended Event sessions.

    .EXAMPLE
    Get-DbaXESession -SqlInstance sqlserver2012 -Session xesession1 | Stop-DbaXESession

    Stops the sessions returned from the Get-DbaXESession function.

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

        [parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$AllSessions,

        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$SessionCollection,
        [switch]$EnableException
    )

    begin {
        # Stop each XESession
        function Stop-XESessions {
            [CmdletBinding()]
            param ([Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions)

            foreach ($xe in $xeSessions) {
                $instance = $xe.Parent.Name
                $session = $xe.Name
                if ($xe.isRunning) {
                    Write-Message -Level Verbose -Message "Stopping XEvent Session $session on $instance."
                    try {
                        $xe.Stop()
                    }
                    catch {
                        Stop-Function -Message "Could not stop XEvent Session on $instance" -Target $session -ErrorRecord $_ -Continue
                    }
                }
                else {
                    Write-Message -Level Warning -Message "$session on $instance is already stopped"
                }
                Get-DbaXESession -SqlInstance $xe.Parent -Session $session
            }
        }
    }

    process {
        if ($SessionCollection) {
            Stop-XESessions $SessionCollection
        }
        else {
            foreach ($instance in $SqlInstance) {
                $xeSessions = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential

                # Filter xesessions based on parameters
                if ($Session) {
                    $xeSessions = $xeSessions | Where-Object { $_.Name -in $Session }
                }
                elseif ($AllSessions) {
                    $systemSessions = @('AlwaysOn_health', 'system_health', 'telemetry_xevents')
                    $xeSessions = $xeSessions | Where-Object { $_.Name -notin $systemSessions }
                }

                Stop-XESessions $xeSessions
            }
        }
    }
}