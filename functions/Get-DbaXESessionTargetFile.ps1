function Get-DbaXESessionTargetFile {
    <#
    .SYNOPSIS
        Get a file system object from the Extended Events Session Target Files.

    .DESCRIPTION
        Get a file system object from the Extended Events Session Target Files.

        Note: this performs a Get-ChildItem on remote servers if the specified target SQL Server is remote.

    .PARAMETER SqlInstance
        The target SQL Server

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Session
        Only return files from a specific session. Options for this parameter are auto-populated from the server.

    .PARAMETER Target
        Only return files from a specific target.

    .PARAMETER InputObject
        Allows results from piping in Get-DbaXESessionTarget.

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
        https://dbatools.io/Get-DbaXESessionTargetFile

    .EXAMPLE
        PS C:\> Get-DbaXESessionTargetFile -SqlInstance sql2017 -Session 'Long Running Queries'

        Shows Target Files for the 'Long Running Queries' session on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance sql2016 -Session 'Long Running Queries' | Get-DbaXESessionTarget | Get-DbaXESessionTargetFile

        Returns the Target Files for the system_health session on sql2016.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(ValueFromPipeline, ParameterSetName = "instance", Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Session,
        [string[]]$Target,
        [parameter(ValueFromPipeline, ParameterSetName = "piped", Mandatory)]
        [Microsoft.SqlServer.Management.XEvent.Target[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaXESessionTarget -SqlInstance $instance -SqlCredential $SqlCredential -Session $Session -Target $Target | Where-Object File -ne $null
        }

        foreach ($object in $InputObject) {
            $computer = [dbainstance]$object.ComputerName
            try {
                if ($computer.IsLocal) {
                    $file = $object.TargetFile
                    Write-Message -Level Verbose -Message "Getting $file"
                    Get-ChildItem "$file*" -ErrorAction Stop
                } else {
                    $file = $object.RemoteTargetFile
                    Write-Message -Level Verbose -Message "Getting $file"
                    Get-ChildItem -Recurse "$file*" -ErrorAction Stop
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}