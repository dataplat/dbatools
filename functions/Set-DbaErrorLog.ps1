function Set-DbaErrorLog {
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

        .PARAMETER LogCount
            Integer value between 6 and 99 for setting the number of error log files to keep for SQL Server instance.

        .PARAMETER LogSize
            Integer value for the size in KB that you want the error log file to grow. This is feature only in SQL Server 2012 and higher. When the file reaches that limit SQL Server will roll the error log over.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Instance, ErrorLog
            Author: Shawn Melton (@wsmelton)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Set-DbaErrorLog

       .EXAMPLE
            Set-DbaErrorLog -SqlInstance sql2017,sql2014 -LogCount 25

            Sets the number of error log files to 25 on sql2017 and sql2014

        .EXAMPLE
            Set-DbaErrorLog -SqlInstance sql2014 -LogSize 1024

            Sets the size of the error log file, before it rolls over, to 1024KB (1MB) on sql2014

        .EXAMPLE
            Set-DbaErrorLog -SqlInstance sql2012 -LogCount 25 -LogSize 500

            Sets the number of error log files to 25 and size before it will roll over to 500KB on sql2012
    #>
    [cmdletbinding(SupportsShouldProcess)]
    param(
        [Parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateRange(6, 99)]
        [int]$LogCount,
        [int]$LogSize,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            $currentNumLogs = $server.NumberOfLogFiles
            $currentLogSize = $server.ErrorLogSizeKb
            
            $collection = [PSCustomObject]@{
                ComputerName              = $server.NetName
                InstanceName              = $server.ServiceName
                SqlInstance               = $server.DomainInstanceName
                LogCount                  = $currentNumLogs
                LogSize                   = $currentLogSize
            }
            
            if (Test-Bound -ParameterName 'LogCount') {
                if ($LogCount -eq $currentNumLogs) {
                    Stop-Function -Message "The provided value for LogCount is already set on $instance" -Continue -Target $instance
                }
                else {
                    if ($PSCmdlet.ShouldProcess($server, "Setting number of logs from [$currentNumLogs] to [$LogCount]")) {
                        try {
                            $server.NumberOfLogFiles = $LogCount
                            $server.Alter()
                        }
                        catch {
                            Stop-Function -Message "Issue setting number of log files on $instance" -Target $instance -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
                        }
                    }
                    if ($PSCmdlet.ShouldProcess($server, "Output final results of setting number of log files")) {
                        $server.Refresh()
                        $collection.LogCount = $server.NumberOfLogFiles
                    }
                }
            }
            if (Test-Bound -ParameterName 'LogSize') {
                if ($LogSize -eq $currentLogSize) {
                    Stop-Function -Message "The provided value for LogSize is already set on $instance" -Target $server -Continue
                }
                else {
                    if ($PSCmdlet.ShouldProcess($server, "Updating log size from [$currentLogSize] to [$LogSize]")) {
                        try {
                            $server.ErrorLogSizeKb = $LogSize
                            $server.Alter()
                        }
                        catch {
                            Stop-Function -Message "Issue setting number of log files on $instance" -Target $instance -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
                        }
                    }
                    if ($PSCmdlet.ShouldProcess($server, "Output final results of setting error log size")) {
                        $server.Refresh()
                        $collection.LogSize = $server.ErrorLogSizeKb
                    }
                }
            }
            $collection
        }
    }
}