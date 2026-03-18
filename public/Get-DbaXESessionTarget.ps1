function Get-DbaXESessionTarget {
    <#
    .SYNOPSIS
        Retrieves Extended Events session targets with their configurations and file locations.

    .DESCRIPTION
        Returns detailed information about Extended Events session targets including their properties, file paths, and current status. This function helps DBAs examine where Extended Events data is being captured, whether sessions are running or stopped, and provides both local and UNC file paths for easy access to target files. Use this when you need to locate XE log files, verify target configurations, or troubleshoot Extended Events sessions that aren't capturing data as expected.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        Filters results to specific Extended Events sessions by name. Supports wildcards and multiple session names.
        Use this when you only need target information from particular XE sessions instead of all sessions on the instance.

    .PARAMETER Target
        Filters results to specific target types such as 'event_file', 'ring_buffer', or 'event_counter'. Supports multiple target names.
        Use this when you need information about particular target types, like finding all file-based targets or checking ring buffer configurations.

    .PARAMETER InputObject
        Accepts Extended Events session objects from Get-DbaXESession through the pipeline. Allows chaining commands for more complex filtering.
        Use this when you've already retrieved specific XE sessions and want to examine their targets without re-querying the server.

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
        https://dbatools.io/Get-DbaXESessionTarget

    .OUTPUTS
        Microsoft.SqlServer.Management.XEvent.Target

        Returns one Target object per Extended Events session target found on the specified SQL Server instance(s). One target can be any kind of data collector configured for a session (event files, ring buffers, event counters, etc.).

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Session: The name of the Extended Events session containing this target
        - SessionStatus: Current session status - either "Running" or "Stopped"
        - Name: The target type/name (e.g., 'package0.event_file', 'package0.ring_buffer')
        - ID: Unique identifier for this target within the session
        - Field: Collection of target field configuration parameters
        - PackageName: The Extended Events package name that provides this target type (usually 'package0')
        - File: Array of resolved file paths for file-based targets (includes UNC paths for network access)
        - Description: Description of the target type and its purpose
        - ScriptName: The target name formatted for scripting purposes

        Additional properties added as NoteProperties:
        - TargetFile: Array of resolved file paths for this target (local paths)
        - RemoteTargetFile: Array of UNC paths for this target (for remote file access)

        Additional properties available from SMO Target object (via Select-Object *):
        - TargetFields: Collection containing detailed configuration parameters for the target
        - State: SMO object state (Existing, Creating, Pending, etc.)
        - Urn: Unified Resource Name for the target object
        - IdentityKey: Identity key of the target object
        - KeyChain: Identity path of the object
        - ModuleID: Module identifier for the target
        - Parent: Reference to parent Session object
        - Properties: Collection of property objects for this target

    .EXAMPLE
        PS C:\> Get-DbaXESessionTarget -SqlInstance ServerA\sql987 -Session system_health

        Shows targets for the system_health session on ServerA\sql987.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2016 -Session system_health | Get-DbaXESessionTarget

        Returns the targets for the system_health session on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2016 -Session system_health | Get-DbaXESessionTarget -Target package0.event_file

        Return only the package0.event_file target for the system_health session on sql2016.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(ValueFromPipeline, ParameterSetName = "instance", Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Session,
        [string[]]$Target,
        [parameter(ValueFromPipeline, ParameterSetName = "piped", Mandatory)]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [switch]$EnableException
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
                            $remotefile += Join-AdminUnc -servername $server.ComputerName -filepath $file
                        }
                    }

                    Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
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