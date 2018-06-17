function Get-DbaSqlLogConfig {
    [cmdletbinding()]
    param(
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
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

            $numLogs = $server.NumberOfLogFiles
            if ($server.VersionMajor -ge 11) {
                $logSize = $server.ErrorLogSizeKb
            }
            else {
                $null
            }

            [PSCustomObject]@{
                ComputerName    = $server.NetName
                InstanceName    = $server.ServiceName
                SqlInstance     = $server.DomainInstanceName
                NumberErrorLogs = $numLogs
                ErrorLogSizeKb  = $logSize
            }
        }
    }
}