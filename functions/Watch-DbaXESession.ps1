function Watch-DbaXESession {
    <#
        .SYNOPSIS
            Watch live XEvent Data as it happens

        .DESCRIPTION
            Watch live XEvent Data as it happens. This command runs until you stop the session, kill the PowerShell session, or Ctrl-C.

            Thanks to Dave Mason (@BeginTry) for some straightforward code samples https://itsalljustelectrons.blogspot.be/2017/01/SQL-Server-Extended-Event-Handling-Via-Powershell.html

        .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

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
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Watch-DbaXESession

        .EXAMPLE
            Watch-DbaXESession -SqlInstance sql2017 -Session system_health

            Shows events for the system_health session as it happens.

        .EXAMPLE
            Watch-DbaXESession -SqlInstance sql2017 -Session system_health | Export-Csv -NoTypeInformation -Path C:\temp\system_health.csv

            Exports live events to CSV. Ctrl-C may not not cancel out of it - fastest way is to stop the session.
        
        .EXAMPLE
            Get-DbaXESession -SqlInstance sql2017 -Session system_health | Start-DbaXESession | Watch-DbaXESession | Export-Csv -NoTypeInformation -Path C:\temp\system_health.csv

            Exports live events to CSV. Ctrl-C may not not cancel out of this. The fastest way to do so is to stop the session.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(ValueFromPipeline, ParameterSetName = "instance", Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Session,
        [parameter(ValueFromPipeline, ParameterSetName = "piped", Mandatory)]
        [Microsoft.SqlServer.Management.XEvent.Session]$InputObject,
        [switch]$Raw,
        [switch][Alias('Silent')]
        $EnableException
    )
    process {
        if (-not $SqlInstance) {
            $server = $InputObject.Parent
        }
        else {
            try {
                Write-Message -Level Verbose -Message "Connecting to $SqlInstance."
                $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue
            }
            $SqlConn = $server.ConnectionContext.SqlConnectionObject
            $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
            $XEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
            Write-Message -Level Verbose -Message "Getting XEvents Sessions on $SqlInstance."
            $InputObject = $XEStore.sessions | Where-Object Name -eq $Session | Select-Object -First 1
        }
        
        if ($InputObject) {
            $status = $InputObject.Status
            if ($status -ne "Running") {
                Stop-Function -Message "$($InputObject.Name) is in a $status state."
                return
            }
            
            # Setup all columns for csv but do it in an order
            $columns = @("name", "timestamp")
            $newcolumns = @()
            
            $fields = ($InputObject.Events.EventFields.Name | Select-Object -Unique)
            foreach ($column in $fields) {
                $newcolumns += $column.TrimStart("collect_")
            }
            
            $actions = ($InputObject.Events.Actions.Name | Select-Object -Unique)
            foreach ($action in $actions) {
                $newcolumns += ($action -Split '\.')[-1]
            }
            
            $newcolumns = $newcolumns | Sort-Object
            $columns = ($columns += $newcolumns) | Select-Object -Unique
            
            try {
                $xevent = New-Object -TypeName Microsoft.SqlServer.XEvent.Linq.QueryableXEventData(
                    ($server.ConnectionContext.ConnectionString),
                    ($InputObject.Name),
                    [Microsoft.SqlServer.XEvent.Linq.EventStreamSourceOptions]::EventStream,
                    [Microsoft.SqlServer.XEvent.Linq.EventStreamCacheOptions]::DoNotCache
                )
                
                if ($raw) {
                    return $xevent
                }
                
                # Format output
                foreach ($event in $xevent) {
                    $hash = [ordered]@{}
                    
                    foreach ($column in $columns) {
                        $null = $hash.Add($column, $event.$column) # this basically adds name and timestamp then nulls
                    }
                    
                    foreach ($action in $event.Actions) {
                        $hash[$action.Name] = $action.Value
                    }
                    
                    foreach ($field in $event.Fields) {
                        $hash[$field.Name] = $field.Value
                    }
                    
                    [pscustomobject]($hash)
                }
            }
            catch {
                Start-Sleep 1
                $status = Get-DbaXESession -SqlInstance $server -Session $Session
                if ($status.Status -ne "Running") {
                    Stop-Function -Message "$($InputObject.Name) was stopped."
                }
                else {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $session
                }
            }
            finally {
                if ($xevent -is [IDisposable]) {
                    $xevent.Dispose()
                }
            }
        }
        else {
            Stop-Function -Message "Session not found." -Target $session
        }
    }
}