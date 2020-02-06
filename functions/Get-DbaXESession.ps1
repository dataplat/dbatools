function Get-DbaXESession {
    <#
    .SYNOPSIS
        Gets a list of Extended Events Sessions from the specified SQL Server instance(s).

    .DESCRIPTION
        Retrieves a list of Extended Events Sessions present on the specified SQL Server instance(s).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        Only return specific sessions. Options for this parameter are auto-populated from the server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaXESession

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance ServerA\sql987

        Returns a custom object with ComputerName, SQLInstance, Session, StartTime, Status and other properties.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance ServerA\sql987 | Format-Table ComputerName, SqlInstance, Session, Status -AutoSize

        Returns a formatted table displaying ComputerName, SqlInstance, Session, and Status.

    .EXAMPLE
        PS C:\> 'ServerA\sql987','ServerB' | Get-DbaXESession

        Returns a custom object with ComputerName, SqlInstance, Session, StartTime, Status and other properties, from multiple SQL instances.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Sessions")]
        [object[]]$Session,
        [switch]$EnableException
    )
    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11 -AzureUnsupported
                $SqlConn = $server.ConnectionContext.SqlConnectionObject
                $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
                $XEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

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
                        $remotefile += Join-AdminUnc -servername $server.ComputerName -filepath $file
                    }
                }

                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Status -Value $status
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Session -Value $x.Name
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name TargetFile -Value $filecollection
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name RemoteTargetFile -Value $remotefile
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Parent -Value $server
                Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Store -Value $XEStore
                Select-DefaultView -InputObject $x -Property ComputerName, InstanceName, SqlInstance, Name, Status, StartTime, AutoStart, State, Targets, TargetFile, Events, MaxMemory, MaxEventSize
            }
        }
    }
}