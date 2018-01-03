function Get-DbaXESession {
    <#
    .SYNOPSIS
    Get a list of Extended Events Sessions

    .DESCRIPTION
    Retrieves a list of Extended Events Sessions

    .PARAMETER SqlInstance
    The SQL Instances that you're connecting to.

    .PARAMETER SqlCredential
    Credential object used to connect to the SQL Server as a different user

    .PARAMETER Session
    Only return specific sessions. This parameter is auto-populated.

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Memory
    Author: Klaas Vandenberghe ( @PowerDBAKlaas )
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Get-DbaXESession

    .EXAMPLE
    Get-DbaXESession -SqlInstance ServerA\sql987

    Returns a custom object with ComputerName, SQLInstance, Session, StartTime, Status and other properties.

    .EXAMPLE
    Get-DbaXESession -SqlInstance ServerA\sql987 | Format-Table ComputerName, SqlInstance, Session, Status -AutoSize

    Returns a formatted table displaying ComputerName, SqlInstance, Session, and Status.

    .EXAMPLE
    'ServerA\sql987','ServerB' | Get-DbaXESession

    Returns a custom object with ComputerName, SqlInstance, Session, StartTime, Status and other properties, from multiple SQL Instances.

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Sessions")]
        [object[]]$Session,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-DbaXEsSession
    }

    process {

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $SqlConn = $server.ConnectionContext.SqlConnectionObject
            $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
            $XEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
            Write-Message -Level Verbose -Message "Getting XEvents Sessions on $instance."

            $xesessions = $XEStore.sessions

            if ($Session) {
                $xesessions = $xesessions | Where-Object { $_.Name -in $Session }
            }

            foreach ($x in $xesessions) {
                $status = switch ($x.IsRunning) { $true { "Running" } $false { "Stopped" } }
                $files = $x.Targets.TargetFields | Where-Object Name -eq Filename | Select-Object -ExpandProperty Value

                $filecollection = $remotefile = @()

                if ($files) {
                    foreach ($file in $files) {
                        if ($file -notmatch ':\\' -and $file -notmatch '\\\\') {
                            $directory = $server.ErrorLogPath.TrimEnd("\")
                            $file = "$directory\$file"
                        }
                        $filecollection += $file
                        $remotefile += Join-AdminUnc -servername $server.netName -filepath $file
                    }
                }

                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Status -Value $status
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Session -Value $x.Name
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name TargetFile -Value $filecollection
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name RemoteTargetFile -Value $remotefile
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Parent -Value $server

                Select-DefaultView -InputObject $x -Property ComputerName, InstanceName, SqlInstance, Name, Status, StartTime, AutoStart, State, Targets, TargetFile, Events, MaxMemory, MaxEventSize
            }
        }
    }
}