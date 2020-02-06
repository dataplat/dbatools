function Set-DbaErrorLogConfig {
    <#
    .SYNOPSIS
        Set the configuration for the ErrorLog on a given SQL Server instance

    .DESCRIPTION
        Sets the number of log files configured on all versions, and size in KB in SQL Server 2012+ and above.

        To set the Path to the ErrorLog, use Set-DbaStartupParameter -ErrorLog. Note that this command requires
        remote, administrative access to the Windows/WMI server, similar to SQL Configuration Manager.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        Author: Shawn Melton (@wsmelton), https://wsmelton.github.com

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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