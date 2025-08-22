function Watch-DbaXESession {
    <#
    .SYNOPSIS
        Monitors Extended Events sessions in real-time, streaming live event data as it occurs

    .DESCRIPTION
        Streams live event data from running Extended Events sessions, allowing real-time monitoring of database activity, performance issues, or security events. Each captured event is processed into a PowerShell object with organized columns for event name, timestamp, fields, and actions. This command runs continuously until you stop the XE session, terminate the PowerShell session, or press Ctrl-C, making it ideal for interactive troubleshooting and live analysis workflows.

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
        If this switch is enabled, the enumeration object is returned.

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
    [CmdletBinding()]
    param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Name")]
        [string]$Session,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [switch]$Raw,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject = Get-DbaXESession -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Session $Session
        }

        foreach ($xesession in $InputObject) {
            $server = $xesession.Parent
            $sessionname = $xesession.Name
            Write-Message -Level Verbose -Message "Watching $sessionname on $($server.Name)."

            if (-not $xesession.IsRunning) {
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
                if ($raw) {
                    return (Read-XEvent -ConnectionString $server.ConnectionContext.ConnectionString -SessionName $sessionname -ErrorAction Stop)
                }

                Read-XEvent -ConnectionString $server.ConnectionContext.ConnectionString -SessionName $sessionname -ErrorAction Stop | ForEach-Object -Process {

                    $hash = [ordered]@{ }

                    foreach ($column in $columns) {
                        $null = $hash.Add($column, $PSItem.$column) # this basically adds name and timestamp then nulls
                    }

                    foreach ($key in $PSItem.Actions.Keys) {
                        $hash[$key] = $PSItem.Actions[$key]
                    }

                    foreach ($key in $PSItem.Fields.Keys) {
                        $hash[$key] = $PSItem.Fields[$key]
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
            }
        }
    }
}