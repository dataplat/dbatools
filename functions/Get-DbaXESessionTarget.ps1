function Get-DbaXESessionTarget {
    <#
        .SYNOPSIS
            Get a list of Extended Events Session Targets from the specified SQL Server instance(s).

        .DESCRIPTION
            Retrieves a list of Extended Events Session Targets from the specified SQL Server instance(s).

        .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Session
            Only return a specific session. Options for this parameter are auto-populated from the server.

        .PARAMETER Target
            Only return a specific target.

        .PARAMETER InputObject
            Specifies an XE session returned by Get-DbaXESession to search.

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
            https://dbatools.io/Get-DbaXESessionTarget

        .EXAMPLE
            Get-DbaXESessionTarget -SqlInstance ServerA\sql987 -Session system_health

            Shows targets for the system_health session on ServerA\sql987.

        .EXAMPLE
            Get-DbaXESession -SqlInstance sql2016 -Session system_health | Get-DbaXESessionTarget

            Returns the targets for the system_health session on sql2016.

        .EXAMPLE
            Get-DbaXESession -SqlInstance sql2016 -Session system_health | Get-DbaXESessionTarget -Target package0.event_file

            Return only the package0.event_file target for the system_health session on sql2016.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(ValueFromPipeline, ParameterSetName = "instance", Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Session,
        [string[]]$Target,
        [parameter(ValueFromPipeline, ParameterSetName = "piped", Mandatory)]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [switch][Alias('Silent')]
        $EnableException
    )
    
    begin {
        function Get-Target {
            [CmdletBinding()]
            param (
                $Sessions,
                $Session,
                $Server,
                $Target
            )
            
            foreach ($xsession in $Sessions) {
                
                if ($null -eq $server) {
                    $server = $xsession.Parent
                }
                
                if ($Session -and $xsession.Name -notin $Session) { continue }
                $status = switch ($xsession.IsRunning) { $true { "Running" } $false { "Stopped" } }
                $sessionname = $xsession.Name
                
                foreach ($xtarget in $xsession.Targets) {
                    if ($Target -and $xtarget.Name -notin $Target) { continue }
                    
                    $files = $xtarget.TargetFields | Where-Object Name -eq Filename | Select-Object -ExpandProperty Value
                    
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
                    
                    Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                    Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name Session -Value $sessionname
                    Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name SessionStatus -Value $status
                    Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name TargetFile -Value $filecollection
                    Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name RemoteTargetFile -Value $remotefile
                    
                    Select-DefaultView -InputObject $xtarget -Property ComputerName, InstanceName, SqlInstance, Session, SessionStatus, Name, ID, 'TargetFields as Field', PackageName, 'TargetFile as File', Description, ScriptName
                }
            }
        }
    }
    
    process {
        if (Test-FunctionInterrupt) { return }
        
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential -Session $Session
        }
        Get-Target -Sessions $InputObject -Session $Session -Target $Target
    }
}