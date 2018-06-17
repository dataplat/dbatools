function Set-DbaSqlLog {
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