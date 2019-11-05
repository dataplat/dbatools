function New-DbaXESmartReplay {
    <#
    .SYNOPSIS
        This response type can be used to replay execution related events to a target SQL Server instance.

    .DESCRIPTION
        This response type can be used to replay execution related events to a target SQL Server instance. The events that you can replay are of the type sql_batch_completed and rpc_completed: all other events are ignored.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Name of the initial catalog to connect to. Statements will be replayed by changing database to the same database where the event was originally captured, so this property only controls the initial database to connect to.

    .PARAMETER Event
        Each Response can be limited to processing specific events, while ignoring all the other ones. When this attribute is omitted, all events are processed.

    .PARAMETER Filter
        Specifies a filter expression in the same form as you would use in the WHERE clause of a SQL query.

        Example: duration > 10000 AND cpu_time > 10000

    .PARAMETER DelaySeconds
        Specifies the duration of the delay in seconds.

    .PARAMETER ReplayIntervalSeconds
        Specifies the duration of the replay interval in seconds.

    .PARAMETER StopOnError
        If this switch is enabled, the replay will be stopped when the first error is encountered. By default, error messages are piped to the log and console output, and replay proceeds.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent, SmartTarget
        Author: Chrissy LeMaire (@cl) | SmartTarget by Gianluca Sartori (@spaghettidba)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaXESmartReplay

    .EXAMPLE
        PS C:\> $response = New-DbaXESmartReplay -SqlInstance sql2017 -Database planning
        PS C:\> Start-DbaXESmartTarget -SqlInstance sql2016 -Session loadrelay -Responder $response

        Replays events from sql2016 on sql2017 in the planning database. Returns a PowerShell job object.

        To see a list of all SmartTarget job objects, use Get-DbaXESmartTarget.

    .EXAMPLE
        PS C:\> $response = New-DbaXESmartReplay -SqlInstance sql2017 -Database planning
        PS C:\> Start-DbaXESmartTarget -SqlInstance sql2017 -Session 'Profiler Standard' -Responder $response -NotAsJob

        Replays events from the 'Profiler Standard' session on sql2016 to sql2017's planning database. Does not run as a job so you can see the raw output.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database,
        [string[]]$Event = "sql_batch_completed",
        [string]$Filter,
        [int]$DelaySeconds,
        [switch]$StopOnError,
        [int]$ReplayIntervalSeconds,
        [switch]$EnableException
    )
    begin {
        try {
            Add-Type -Path "$script:PSModuleRoot\bin\libraries\third-party\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll" -ErrorRecord $_ -Target "XESmartTarget"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($Pscmdlet.ShouldProcess($instance, "Creating new XESmartReply")) {
                Write-Message -Message "Making a New XE SmartReplay for $Event against $instance running on $($server.name)" -Level Verbose
                try {
                    $replay = New-Object -TypeName XESmartTarget.Core.Responses.ReplayResponse
                    $replay.ServerName = $instance
                    $replay.DatabaseName = $Database
                    $replay.Events = $Event
                    $replay.StopOnError = $StopOnError
                    $replay.Filter = $Filter
                    $replay.DelaySeconds = $DelaySeconds
                    $replay.ReplayIntervalSeconds = $ReplayIntervalSeconds

                    if ($SqlCredential) {
                        $replay.UserName = $SqlCredential.UserName
                        $replay.Password = $SqlCredential.GetNetworkCredential().Password
                    }

                    $replay
                } catch {
                    $message = $_.Exception.InnerException.InnerException | Out-String
                    Stop-Function -Message $message -Target "XESmartTarget" -Continue
                }
            }
        }
    }
}