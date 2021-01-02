function Watch-DbaXESession {
    <#
    .SYNOPSIS
        Watch live XEvent Data as it happens

    .DESCRIPTION
        Watch live XEvent Data as it happens. This command runs until you stop the session, kill the PowerShell session, or Ctrl-C.

        Thanks to Dave Mason (@BeginTry) for some straightforward code samples https://itsalljustelectrons.blogspot.be/2017/01/SQL-Server-Extended-Event-Handling-Via-Powershell.html

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        Only return a specific session. Options for this parameter are auto-populated from the server.

    .PARAMETER Raw
        If this switch is enabled, the Microsoft.SqlServer.XEvent.Linq.QueryableXEventData enumeration object is returned.

    .PARAMETER InputObject
        Accepts an XESession object returned by Get-DbaXESession.

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
        https://dbatools.io/Watch-DbaXESession

    .EXAMPLE
        PS C:\> Watch-DbaXESession -SqlInstance sql2017 -Session system_health

        Shows events for the system_health session as it happens.

    .EXAMPLE
        PS C:\> Watch-DbaXESession -SqlInstance sql2017 -Session system_health | Export-Csv -NoTypeInformation -Path C:\temp\system_health.csv

        Exports live events to CSV. Ctrl-C may not not cancel out of it - fastest way is to stop the session.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2017 -Session system_health | Start-DbaXESession | Watch-DbaXESession | Export-Csv -NoTypeInformation -Path C:\temp\system_health.csv

        Exports live events to CSV. Ctrl-C may not not cancel out of this. The fastest way to do so is to stop the session.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(ValueFromPipeline, ParameterSetName = "instance", Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Session,
        [parameter(ValueFromPipeline, ParameterSetName = "piped", Mandatory)]
        [Microsoft.SqlServer.Management.XEvent.Session]$InputObject,
        [switch]$Raw,
        [switch]$EnableException
    )
    process {
        if (-not $SqlInstance) {

        } else {
            try {
                $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue
            }
            $SqlConn = $server.ConnectionContext.SqlConnectionObject
            $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
            $XEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
            Write-Message -Level Verbose -Message "Getting XEvents Sessions on $SqlInstance."
            $InputObject += $XEStore.sessions | Where-Object Name -eq $Session
        }

        foreach ($xesession in $InputObject) {
            $server = $xesession.Parent
            $sessionname = $xesession.Name
            Write-Message -Level Verbose -Message "Watching $sessionname on $($server.Name)."

            if (-not $xesession.IsRunning -and -not $xesession.IsRunning) {
                Stop-Function -Message "$($xesession.Name) is not running on $($server.Name)" -Continue
            }

            # Setup all columns for csv but do it in an order
            $columns = @("name", "timestamp")
            $newcolumns = @()

            $fields = ($xesession.Events.EventFields.Name | Select-Object -Unique)
            foreach ($column in $fields) {
                $newcolumns += $column.TrimStart("collect_")
            }

            $actions = ($xesession.Events.Actions.Name | Select-Object -Unique)
            foreach ($action in $actions) {
                $newcolumns += ($action -Split '\.')[-1]
            }

            $newcolumns = $newcolumns | Sort-Object
            $columns = ($columns += $newcolumns) | Select-Object -Unique

            try {
                $xevent = New-Object -TypeName Microsoft.SqlServer.XEvent.Linq.QueryableXEventData(
                    ($server.ConnectionContext.ConnectionString),
                    ($xesession.Name),
                    [Microsoft.SqlServer.XEvent.Linq.EventStreamSourceOptions]::EventStream,
                    [Microsoft.SqlServer.XEvent.Linq.EventStreamCacheOptions]::DoNotCache
                )

                if ($raw) {
                    return $xevent
                }

                # Format output
                foreach ($event in $xevent) {
                    $hash = [ordered]@{ }

                    foreach ($column in $columns) {
                        $null = $hash.Add($column, $event.$column) # this basically adds name and timestamp then nulls
                    }

                    foreach ($action in $event.Actions) {
                        $hash[$action.Name] = $action.Value
                    }

                    foreach ($field in $event.Fields) {
                        $hash[$field.Name] = $field.Value
                    }

                    [PSCustomObject]($hash)
                }
            } catch {
                Start-Sleep 1
                $status = Get-DbaXESession -SqlInstance $server -Session $sessionname
                if ($status.Status -ne "Running") {
                    Stop-Function -Message "$($xesession.Name) was stopped."
                } else {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $sessionname
                }
            } finally {
                if ($xevent -is [IDisposable]) {
                    $xevent.Dispose()
                }
            }
        }
    }
}