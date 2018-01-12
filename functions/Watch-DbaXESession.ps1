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
    Watch-DbaXESession -SqlInstance ServerA\sql987 -Session system_health

    Shows events for the system_health session as it happens

    .EXAMPLE
    Get-DbaXESession  -SqlInstance sql2016 -Session system_health | Watch-DbaXESession | Select -ExpandProperty Fields

    Also shows events for the system_health session as it happens and expands the Fields property. Looks a bit like this

    Name                Type                                   Value
    ----                ----                                   -----
    id                  System.UInt32                              0
    timestamp           System.UInt64                              0
    process_utilization System.UInt32                              0
    system_idle         System.UInt32                             99
    user_mode_time      System.UInt64                        8906250
    kernel_mode_time    System.UInt64                         468750
    page_faults         System.UInt32                             60
    working_set_delta   System.Int64                               0
    memory_utilization  System.UInt32                             99

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
        [switch][Alias('Silent')]$EnableException
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
            $status = (Get-DbaXESession -SqlInstance $server -Session $InputObject.Name).Status
            if ($status -ne "Running") {
                Stop-Function -Message "$($InputObject.Name) is in a $status state"
                return
            }
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
                        $columns = "name", "timestamp"
                        foreach ($action in $event.Actions) {
                            $columns += $action.Name
                            Add-Member -InputObject $event -NotePropertyName $action.Name -NotePropertyValue $action.Value
                        }
                        
                        foreach ($field in $event.Fields) {
                            $columns += $field.Name
                            Add-Member -Force -InputObject $event -NotePropertyName $field.Name -NotePropertyValue $field.Value
                        }
                        Select-DefaultView -InputObject $event -Property $columns #-ExcludeProperty Fields, Actions, UUID, Package, Metadata, Location
                    }
                }
            }
            catch {
                if ((Get-DbaXESession -SqlInstance $server -Session $Session)) {
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