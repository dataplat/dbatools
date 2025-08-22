function Remove-DbaXESession {
    <#
    .SYNOPSIS
        Removes Extended Events sessions from SQL Server instances.

    .DESCRIPTION
        Removes Extended Events sessions from SQL Server instances, giving you the option to target specific sessions by name or remove all user-created sessions at once. This function preserves critical system sessions (system_health, telemetry_xevents, and AlwaysOn_health) when using the AllSessions parameter, so you can safely clean up monitoring sessions without breaking SQL Server's built-in diagnostics. Useful for removing outdated monitoring configurations or cleaning up test sessions that are no longer needed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        Specifies a list of Extended Events sessions to remove.

    .PARAMETER AllSessions
        If this switch is enabled, all Extended Events sessions will be removed except the packaged sessions AlwaysOn_health, system_health, telemetry_xevents.

    .PARAMETER InputObject
        Accepts a collection of XEsession objects as output by Get-DbaXESession.

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
        https://dbatools.io/Remove-DbaXESession

    .EXAMPLE
        PS C:\> Remove-DbaXESession -SqlInstance sql2012 -AllSessions

        Removes all Extended Event Session on the sqlserver2014 instance.

    .EXAMPLE
        PS C:\> Remove-DbaXESession -SqlInstance sql2012 -Session xesession1,xesession2

        Removes the xesession1 and xesession2 Extended Event sessions.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2017 | Remove-DbaXESession -Confirm:$false

        Removes all sessions from sql2017, bypassing prompts.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2012 -Session xesession1 | Remove-DbaXESession

        Removes the sessions returned from the Get-DbaXESession function.

    #>
    [CmdletBinding(DefaultParameterSetName = 'Session', SupportsShouldProcess, ConfirmImpact = 'High')]
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
        [Alias("Name")]
        [object[]]$Session,
        [parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$AllSessions,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        # Remove each XESession
        function Remove-XESessions {
            [CmdletBinding(SupportsShouldProcess)]
            param ([Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions)

            foreach ($xe in $xeSessions) {
                $instance = $xe.Parent.Name
                $session = $xe.Name

                if ($Pscmdlet.ShouldProcess("$instance", "Removing XEvent Session $session")) {
                    try {
                        $xe.Drop()
                        [PSCustomObject]@{
                            ComputerName = $xe.Parent.ComputerName
                            InstanceName = $xe.Parent.ServiceName
                            SqlInstance  = $xe.Parent.DomainInstanceName
                            Session      = $session
                            Status       = "Removed"
                        }
                    } catch {
                        Stop-Function -Message "Could not remove XEvent Session on $instance" -Target $session -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }

    process {
        if ($InputObject) {
            # avoid the collection issue
            $sessions = Get-DbaXESession -SqlInstance $InputObject.Parent -Session $InputObject.Name
            foreach ($item in $sessions) {
                Remove-XESessions $item
            }
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

                Remove-XESessions $xeSessions
            }
        }
    }
}