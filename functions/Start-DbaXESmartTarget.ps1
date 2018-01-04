function Start-DbaXESmartTarget {
 <#
    .SYNOPSIS
    XESmartTarget runs as a client application for an Extended Events session running on a SQL Server instance

    .DESCRIPTION
    XESmartTarget offers the ability to set up complex actions in response to Extended Events captured in sessions, without writing a single line of code.

    See more: https://github.com/spaghettidba/XESmartTarget/wiki

    .PARAMETER SqlInstance
    The SQL Instances that you're connecting to

    .PARAMETER SqlCredential
    Credential object used to connect to the SQL Server as a different user

    .PARAMETER Session
    Name of the Extended Events session to attach to.

    You can monitor a single session with an instance of XESmartTarget: in case you need to perform action on multiple sessions, run an additional instance of XESmartTarget, with its own configuration file.

    .PARAMETER Database
    Specifies the name of the database that contains the target table.

    .PARAMETER FailOnProcessingError
    Fail on processing error.

    .PARAMETER Responder
    The list of responses can include zero or more Response objects, each to be configured by specifying values for their public members.

    .PARAMETER Path
    Path to Json responders

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    SmartTarget: by Gianluca Sartori (@spaghettidba)

    .LINK
    https://dbatools.io/Start-DbaXESmartTarget
    https://github.com/spaghettidba/XESmartTarget/wiki

    .EXAMPLE
    $emailresponse = New-DbaXESmartEmail -SmtpServer smtp.ad.local -To admin@ad.local -Sender reports@ad.local
    Start-DbaXESmartTarget -SqlInstance sql2017 -Session telemetry_xevents -Responder $emailresponse

    More info soon

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database,
        [parameter(Mandatory)]
        [string]$Session,
        [switch]$AutoCreateTargetTable,
        [switch]$FailOnProcessingError,
        [object[]]$Responder,
        [string]$Path,
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
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $target = New-Object -TypeName XESmartTarget.Core.Target
            $target.ServerName = $instance
            $target.SessionName = $Session
            $target.FailOnProcessingError = $FailOnProcessingError

            if ($SqlCredential) {
                $target.UserName = $SqlCredential.UserName
                $target.Password = $SqlCredential.GetNetworkCredential().Password
            }

            foreach ($response in $Responder) {
                $target.Responses.Add($response)
            }

            try {
                $target.Start()
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target "XESmartTarget" -Continue
            }
        }
    }
}