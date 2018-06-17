function Set-DbaSqlLog {
    <#
        .SYNOPSIS
            Set the configuration for the ErrorLog on a given SQL Server instance
        .DESCRIPTION
            Set the configuration for the ErrorLog on a given SQL Server instance.
            Includes setting the number of log files configured and/or size in KB (SQL Server 2012+ only)

        .PARAMETER SqlInstance
            The target SQL Server instance(s)

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER NumberOfLog
            Integer value between 6 and 99 for setting the number of error log files to keep for SQL Server instance.

        .PARAMETER SizeInKb
            Integer value for the size in KB that you want the error log file to grow. This is feature only in SQL Server 2012 and higher. When the file reaches that limit SQL Server will roll the error log over.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Configure, Instance, ErrorLog
            Author: Shawn Melton (@wsmelton)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Set-DbaSqlLogConfig

       .EXAMPLE
            Set-DbaSqlLogConfig -SqlInstance server2017,server2014 -NumberOfLog 25

            Sets the number of error log files to 25 on server2017 and server2014

        .EXAMPLE
            Set-DbaSqlLogConfig -SqlInstance server2014 -SizeInKb 1024

            Sets the size of the error log file, before it rolls over, to 1024KB (1GB) on server2014

        .EXAMPLE
            Set-DbaSqlLogConfig -SqlInstance server2012 -NumberOfLog 25 -SizeInKb 500

            Sets the number of error log files to 25 and size before it will roll over to 500KB on server2012
    #>
    [cmdletbinding(SupportsShouldProcess)]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [DbaValidatePattern('^[6-9][0-9]?$', ErrorMessage = "Error processing {0} - input must be an integer between 6 and 99")]
        [int]$NumberOfLog,
        [int]$SizeInKb,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $collectionNumberLog = [PSCustomObject]@{
                ComputerName            = $server.NetName
                InstanceName            = $server.ServiceName
                SqlInstance             = $server.DomainInstanceName
                Setting                 = 'NumberOfLogFiles'
                OriginalNumberErrorLogs = $null
                CurrentNumberErrorLogs  = $null
                Status                  = $null
            }
            $collectionErrorLogSize = [PSCustomObject]@{
                ComputerName           = $server.NetName
                InstanceName           = $server.ServiceName
                SqlInstance            = $server.DomainInstanceName
                Setting                = 'ErrorLogSizeKb'
                OriginalErrorLogSizeKb = $null
                CurrentErrorLogSizeKb  = $null
                Status                 = $null
            }
            if (Test-Bound 'NumberOfLog') {
                try {
                    $currentNumLogs = $server.NumberOfLogFiles
                    $collectionNumberLog.OriginalNumberErrorLogs = $currentNumLogs
                }
                catch {
                    $collectionNumberLog.Status = "Failed collection"
                    $collectionNumberLog
                    Stop-Function -Message "Issue collecting current value for number of error logs" -Target $server -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
                }

                if ($NumberOfLog -eq $currentNumLogs) {
                    if ($PSCmdlet.ShouldProcess($server, "Provide warning that NumberOfLog value already matches the configured value")) {
                        Write-Message -Level Warning -Message "The provided value for NumberOfLog is already set" -Continue
                    }
                }
                else {
                    if ($PSCmdlet.ShouldProcess($server, "Setting number of logs from [$currentNumLogs] to [$NumberOfLog]")) {
                        try {
                            $server.NumberOfLogFiles = $NumberOfLog
                            $server.Alter()
                        }
                        catch {
                            $collectionNumberLog.Status = "Failed update"
                            $collectionNumberLog
                            Stop-Function -Message "Issue setting number of log files" -Target $instance -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
                        }
                    }
                    if ($PSCmdlet.ShouldProcess($server, "Output final results of setting number of log files")) {
                        $server.Refresh()
                        $collectionNumberLog.CurrentNumberErrorLogs = $server.NumberOfLogFiles
                        $collectionNumberLog
                    }
                }
            }
            if (Test-Bound 'SizeInKb') {
                try {
                    $currentSizeInKb = $server.ErrorInSizeKb
                    $collectionErrorLogSize.OriginalErrorLogSizeKb = $currentSizeInKb
                }
                catch {
                    $collectionErrorLogSize.Status = "Failed collection"
                    $collectionErrorLogSize
                    Stop-Function -Message "Issue collecting current value for number of error logs" -Target $server -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
                }

                if ($SizeInKb -eq $currentSizeInKb) {
                    if ($PSCmdlet.ShouldProcess($server, "Provide warning that SizeInKb value already matches the configured value")) {
                        Write-Message -Level Warning -Message "The provided value for SizeInKb is already set" -Continue
                    }
                }
                else {
                    if ($PSCmdlet.ShouldProcess($server, "Setting number of logs from [$currentSizeInKb] to [$SizeInKb]")) {
                        try {
                            $server.ErrorLogSizeKb = $SizeInKb
                            $server.Alter()
                        }
                        catch {
                            $collectionErrorLogSize.Status = "Failed update"
                            $collectionErrorLogSize
                            Stop-Function -Message "Issue setting number of log files" -Target $instance -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
                        }
                    }
                    if ($PSCmdlet.ShouldProcess($server, "Output final results of setting error log size")) {
                        $server.Refresh()
                        $collectionErrorLogSize.CurrentErrorLogSizeKb = $server.ErrorLogSizeKb
                        $collectionErrorLogSize
                    }
                }
            }
        }
    }
}