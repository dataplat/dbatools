function New-DbaXESmartReplay {
    <#
        .SYNOPSIS
            This Response type can be used to replay execution related events to a target SQL Server instance.

        .DESCRIPTION
            This Response type can be used to replay execution related events to a target SQL Server instance. The events that you can replay are of the type sql_batch_completed and rpc_completed: all other events are ignored.

        .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

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

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
            SmartTarget: by Gianluca Sartori (@spaghettidba)

        .LINK
            https://dbatools.io/New-DbaXESmartReplay
            https://github.com/spaghettidba/XESmartTarget/wiki

        .EXAMPLE
            $response = New-DbaXESmartReplay -SqlInstance sql2017 -Database planning
            Start-DbaXESmartTarget -SqlInstance sql2016 -Session loadrelay -Responder $response

            Replays events from sql2016 on sql2017 in the planning database. Returns a PowerShell job object.

            To see a list of all SmartTarget job objects, use Get-DbaXESmartTarget.

        .EXAMPLE
            $response = New-DbaXESmartReplay -SqlInstance sql2017 -Database planning
            Start-DbaXESmartTarget -SqlInstance sql2017 -Session 'Profiler Standard' -Responder $response -NotAsJob

            Replays events from the 'Profiler Standard' session on sql2016 to sql2017's planning database. Does not run as a job so you can see the raw output.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
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
            Add-Type -Path "$script:PSModuleRoot\bin\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
        }
        catch {
            Stop-Function -Message "Could not load XESmartTarget.Core.dll" -ErrorRecord $_ -Target "XESmartTarget"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

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
            }
            catch {
                $message = $_.Exception.InnerException.InnerException | Out-String
                Stop-Function -Message $message -Target "XESmartTarget" -Continue
            }
        }
    }
}