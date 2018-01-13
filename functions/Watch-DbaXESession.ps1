function Watch-DbaXESession {
    <#
    .SYNOPSIS
    Watch live XEvent Data as it happens

    .DESCRIPTION
    Watch live XEvent Data as it happens - this command runs until you stop the session, kill the PowerShell session, or Ctrl-C a few hundred times ;).

    Thanks to Dave Mason (@BeginTry) for some straightforward code samples https://itsalljustelectrons.blogspot.be/2017/01/SQL-Server-Extended-Event-Handling-Via-Powershell.html

    .PARAMETER SqlInstance
    The SQL Instance that you're connecting to.

    .PARAMETER SqlCredential
    Credential object used to connect to the SQL Server as a different user

    .PARAMETER Session
    Only return a specific session. This parameter is auto-populated.

    .PARAMETER Raw
    Returns the Microsoft.SqlServer.XEvent.Linq.QueryableXEventData enumeration object

    .PARAMETER InputObject
    Internal parameter

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Xevent
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Watch-DbaXESession

    .EXAMPLE
    Watch-DbaXESession -SqlInstance sql2017 -Session system_health

    Shows events for the system_health session as it happens

    .EXAMPLE
    Watch-DbaXESession -SqlInstance sql2017 -Session system_health | Export-Csv -NoTypeInformation -Path C:\temp\system_health.csv

    Exports live events to CSV. Ctrl-C may not not cancel out of it - fastest way is to stop the session.
    
    .EXAMPLE
    Get-DbaXESession -SqlInstance sql2017 -Session system_health | Start-DbaXESession | Watch-DbaXESession | Export-Csv -NoTypeInformation -Path C:\temp\system_health.csv

    Exports live events to CSV. Ctrl-C may not not cancel out of it - fastest way is to stop the session.
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
                Write-Message -Level Verbose -Message "Connecting to $SqlInstance"
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
                Stop-Function -Message "$($InputObject.Name) is in a $status state"
                return
            }
            
            # Setup all columns
            $columns = @("name", "timestamp")
            foreach ($action in $InputObject.Events.Actions.Name) {
                $columns += ($action -Split '\.')[-1]
            }
            foreach ($column in $InputObject.Events.EventFields.Name) {
                $columns += ($column -Split 'collect_')[-1]
            }
            $columns = $columns | Select-Object -Unique
            
            try {
                $xevent = New-Object -TypeName Microsoft.SqlServer.XEvent.Linq.QueryableXEventData(
                    ($server.ConnectionContext.ConnectionString),
                    ($InputObject.Name),
                    [Microsoft.SqlServer.XEvent.Linq.EventStreamSourceOptions]::EventStream,
                    [Microsoft.SqlServer.XEvent.Linq.EventStreamCacheOptions]::DoNotCache
                )
                
                if ($raw) {
                    foreach ($row in $xevent) {
                        $row
                    }
                }
                else {
                    # make it pretty
                    foreach ($event in $xevent) {
                        foreach ($action in $event.Actions) {
                            #$columns += $action.Name
                            Add-Member -InputObject $event -NotePropertyName $action.Name -NotePropertyValue $action.Value
                        }
                        
                        foreach ($field in $event.Fields) {
                            # $columns += $field.Name
                            Add-Member -Force -InputObject $event -NotePropertyName $field.Name -NotePropertyValue $field.Value
                        }
                        
                        if (-not $forcedcolumns) {
                            foreach ($column in $columns) {
                                if (($event | Get-Member | Select-Object -ExpandProperty Name) -notcontains $column) {
                                    Add-Member -InputObject $event -NotePropertyName $column -NotePropertyValue $null
                                }
                            }
                            $forcedcolumns = $true
                        }
                        
                        Select-DefaultView -InputObject $event -Property $columns #-ExcludeProperty Fields, Actions, UUID, Package, Metadata, Location
                    }
                }
            }
            catch {
                $status = Get-DbaXESession -SqlInstance $server -Session $Session
                if ($status.Status -ne "Running") {
                    Stop-Function -Message "$($InputObject.Name) was stopped"
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
            Stop-Function -Message "Session not found" -Target $session
        }
    }
}