function Start-DbaXESmartTarget {
    <#
        .SYNOPSIS
            XESmartTarget runs as a client application for an Extended Events session running on a SQL Server instance.

        .DESCRIPTION
            XESmartTarget offers the ability to set up complex actions in response to Extended Events captured in sessions, without writing a single line of code.

            See more at https://github.com/spaghettidba/XESmartTarget/wiki

        .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Session
            Name of the Extended Events session to attach to.

            You can monitor a single session with an instance of XESmartTarget. In case you need to perform action on multiple sessions, run an additional instance of XESmartTarget, with its own configuration file.

        .PARAMETER Database
            Specifies the name of the database that contains the target table.

        .PARAMETER FailOnProcessingError
            If this switch is enabled, the a processing error will trigger a failure.

        .PARAMETER Responder
            The list of responses can include zero or more Response objects, each to be configured by specifying values for their public members.

        .PARAMETER Template
            Path to the dbatools built-in templates

        .PARAMETER NotAsJob
            If this switch is enabled, output will be sent to screen indefinitely. BY default, a job will be run in the background.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT
            SmartTarget: by Gianluca Sartori (@spaghettidba)

        .LINK
            https://dbatools.io/Start-DbaXESmartTarget
            https://github.com/spaghettidba/XESmartTarget/wiki

        .EXAMPLE
            $response = New-DbaXESmartQueryExec -SqlInstance sql2017 -Database dbadb -Query "update table set whatever = 1"
            Start-DbaXESmartTarget -SqlInstance sql2017 -Session deadlock_tracker -Responder $response

            Executes a T-SQL command against dbadb on sql2017 whenever a deadlock event is recorded.

        .EXAMPLE
            $response = New-DbaXESmartQueryExec -SqlInstance sql2017 -Database dbadb -Query "update table set whatever = 1"
            $params = @{
                SmtpServer = "smtp.ad.local"
                To = "admin@ad.local"
                Sender = "reports@ad.local"
                Subject = "Query executed"
                Body = "Query executed at {collection_time}"
                Attachment = "batch_text"
                AttachmentFileName = "query.sql"
            }
            $emailresponse = New-DbaXESmartEmail @params
            Start-DbaXESmartTarget -SqlInstance sql2017 -Session querytracker -Responder $response, $emailresponse

            Executes a T-SQL command against dbadb on sql2017 and sends an email whenever a querytracker event is recorded.

        .EXAMPLE
            $columns = "cpu_time", "duration", "physical_reads", "logical_reads", "writes", "row_count", "batch_text"
            $response = New-DbaXESmartTableWriter -SqlInstance sql2017 -Database dbadb -Table deadlocktracker -OutputColumns $columns -Filter "duration > 10000"
            Start-DbaXESmartTarget -SqlInstance sql2017 -Session deadlock_tracker -Responder $response

            Writes Extended Events to the deadlocktracker table in dbadb on sql2017.
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
        [switch]$FailOnProcessingError,
        [object[]]$Responder,
        [string[]]$Template,
        [switch]$NotAsJob,
        [switch]$EnableException
    )
    begin {
        function Start-SmartFunction {
            [CmdletBinding()]
            param (
                [parameter(Mandatory, ValueFromPipeline)]
                [Alias("ServerInstance", "SqlServer")]
                [DbaInstanceParameter[]]$SqlInstance,
                [PSCredential]$SqlCredential,
                [string]$Database,
                [parameter(Mandatory)]
                [string]$Session,
                [switch]$FailOnProcessingError,
                [object[]]$Responder,
                [string[]]$Template,
                [switch]$NotAsJob,
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
                        $message = $_.Exception.InnerException.InnerException | Out-String
                        
                        if ($message) {
                            Stop-Function -Message $message -Target "XESmartTarget" -Continue
                        }
                        else {
                            Stop-Function -Message "Failure" -Target "XESmartTarget" -ErrorRecord $_ -Continue
                        }
                    }
                }
            }
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            if (-not ($xesession = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential -Session $Session)) {
                Stop-Function -Message "Session $Session does not exist on $instance."
                return
            }
            if ($xesession.Status -ne "Running") {
                Stop-Function -Message "Session $Session on $instance is not running."
                return
            }
        }

        if ($NotAsJob) {
            Start-SmartFunction @PSBoundParameters
        }
        else {
            $date = (Get-Date -UFormat "%H%M%S") #"%m%d%Y%H%M%S"
            Start-Job -Name "XESmartTarget-$session-$date" -ArgumentList $PSBoundParameters, $script:PSModuleRoot -ScriptBlock {
                param (
                    $Parameters,
                    $ModulePath
                )
                Import-Module "$ModulePath\dbatools.psd1"
                Add-Type -Path "$ModulePath\bin\XESmartTarget\XESmartTarget.Core.dll" -ErrorAction Stop
                $params = @{
                    SqlInstance    = $Parameters.SqlInstance.InputObject
                    Database       = $Parameters.Database
                    Session        = $Parameters.Session
                    Responder      = @()
                }
                if ($Parameters.SqlCredential) {
                    $params["SqlCredential"] = $Parameters.SqlCredential
                }
                foreach ($responder in $Parameters.Responder) {
                    $typename = $responder.PSObject.TypeNames[0] -replace "^Deserialized\.", ""
                    $newResponder = New-Object -TypeName $typename
                    foreach ($property in $responder.PSObject.Properties) {
                        if ($property.Value) {
                            $name = $property.Name
                            $newResponder.$name = $property.Value
                        }
                    }
                    $params["Responder"] += $newResponder
                }
                
                Start-DbaXESmartTarget @params -NotAsJob -FailOnProcessingError
            } | Select-Object -Property ID, Name, State
        }
    }
}