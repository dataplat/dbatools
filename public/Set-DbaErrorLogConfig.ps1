function Set-DbaErrorLogConfig {
    <#
    .SYNOPSIS
        Configures SQL Server error log retention and size rollover settings

    .DESCRIPTION
        Configures how SQL Server manages its error log files by setting retention count and automatic rollover size. You can specify how many error log files to keep (6-99) across all SQL Server versions, and set the file size limit in KB for automatic rollover on SQL Server 2012 and later.

        This helps DBAs manage disk space and ensure adequate error log history for troubleshooting without manual intervention. When a log file reaches the specified size limit, SQL Server automatically creates a new error log and archives the previous one.

        To set the Path to the ErrorLog, use Set-DbaStartupParameter -ErrorLog. Note that this command requires
        remote, administrative access to the Windows/WMI server, similar to SQL Configuration Manager.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LogCount
        Sets the number of error log files SQL Server retains before deleting the oldest ones. Must be between 6 and 99.
        Use this to balance disk space with troubleshooting history - more files provide longer history but consume more disk space.

    .PARAMETER LogSize
        Sets the maximum size in KB for each error log file before SQL Server automatically creates a new log file. Only available on SQL Server 2012 and later.
        Use this to prevent error logs from growing too large and to ensure regular log rotation without manual intervention.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, ErrorLog, Logging
        Author: Shawn Melton (@wsmelton), wsmelton.github.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaErrorLogConfig

    .EXAMPLE
        PS C:\> Set-DbaErrorLogConfig -SqlInstance sql2017,sql2014 -LogCount 25

        Sets the number of error log files to 25 on sql2017 and sql2014

    .EXAMPLE
        PS C:\> Set-DbaErrorLogConfig -SqlInstance sql2014 -LogSize 102400

        Sets the size of the error log file, before it rolls over, to 102400 KB (100 MB) on sql2014

    .EXAMPLE
        PS C:\> Set-DbaErrorLogConfig -SqlInstance sql2012 -LogCount 25 -LogSize 500

        Sets the number of error log files to 25 and size before it will roll over to 500 KB on sql2012

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
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $currentNumLogs = $server.NumberOfLogFiles
            $currentLogSize = $server.ErrorLogSizeKb

            $collection = [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                LogCount     = $currentNumLogs
                LogSize      = [dbasize]($currentLogSize * 1024)
            }
            if (Test-Bound -ParameterName 'LogSize') {
                if ($server.VersionMajor -lt 11) {
                    Stop-Function -Message "Size is cannot be set on $instance. SQL Server 2008 R2 and below not supported." -Continue
                }
                if ($LogSize -eq $currentLogSize) {
                    Write-Message -Level Warning -Message "The provided value for LogSize is already set to $LogSize KB on $instance"
                } else {
                    if ($PSCmdlet.ShouldProcess($server, "Updating log size from [$currentLogSize] to [$LogSize]")) {
                        try {
                            $server.ErrorLogSizeKb = $LogSize
                            $server.Alter()
                        } catch {
                            Stop-Function -Message "Issue setting number of log files on $instance" -Target $instance -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
                        }
                    }
                    if ($PSCmdlet.ShouldProcess($server, "Output final results of setting error log size")) {
                        $server.Refresh()
                        $collection.LogSize = [dbasize]($server.ErrorLogSizeKb * 1024)
                    }
                }
            }

            if (Test-Bound -ParameterName 'LogCount') {
                if ($LogCount -eq $currentNumLogs) {
                    Write-Message -Level Warning -Message "The provided value for LogCount is already set to $LogCount on $instance"
                } else {
                    if ($PSCmdlet.ShouldProcess($server, "Setting number of logs from [$currentNumLogs] to [$LogCount]")) {
                        try {
                            $server.NumberOfLogFiles = $LogCount
                            $server.Alter()
                        } catch {
                            Stop-Function -Message "Issue setting number of log files on $instance" -Target $instance -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
                        }
                    }
                    if ($PSCmdlet.ShouldProcess($server, "Output final results of setting number of log files")) {
                        $server.Refresh()
                        $collection.LogCount = $server.NumberOfLogFiles
                    }
                }
            }
            $collection
        }
    }
}